// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {CompCommToken} from "src/CompCommToken.sol";

/// @dev Minimal interfaces per docs/IMPLEMENTATION_SPEC.md
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface ICometRewards {
    function claimTo(address comet, address to, bool shouldAccrue) external returns (uint256);
}

/// @title VaultManager
/// @notice Manages portfolio funds with timelock, DeFi integrations, and redemption of WETH for MT holders.
contract VaultManager is Ownable2Step, AccessControl, ReentrancyGuard, Pausable {
    // --------------------
    // Errors
    // --------------------
    error VaultManager__InvalidAddress();
    error VaultManager__AssetNotAllowed();
    error VaultManager__CometNotAllowed();
    error VaultManager__InvalidPhase();
    error VaultManager__AmountZero();
    error VaultManager__SweepRestricted();

    // --------------------
    // Roles
    // --------------------
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // --------------------
    // Constants & Immutables
    // --------------------
    /// @notice Deployment timestamp when timelock begins.
    uint256 public immutable lockStart;

    /// @notice Lock duration: 46,656,000 seconds (18 months).
    uint256 public constant LOCK_DURATION = 46_656_000;

    /// @notice Timestamp when funds unlock (lockStart + LOCK_DURATION).
    uint256 public immutable unlockTimestamp;

    /// @notice WETH token address.
    address public immutable weth;

    /// @notice USDC token address.
    address public immutable usdc;

    /// @notice Uniswap v3 router address.
    address public immutable uniswapV3Router;

    /// @notice Compound v3 CometRewards address.
    address public immutable cometRewards;

    // --------------------
    // Storage
    // --------------------
    /// @notice Whitelist of allowed tokens (WETH, USDC, sUSDC, AERO, etc.).
    mapping(address => bool) public allowedAssets;
    /// @dev Iterable tracking of assets for consolidation checks.
    address[] private _assetList;
    mapping(address => bool) private _assetSeen;

    /// @notice Whitelist of allowed Compound v3 markets.
    mapping(address => bool) public allowedComets;
    /// @dev Iterable tracking of comets for consolidation checks.
    address[] private _cometList;
    mapping(address => bool) private _cometSeen;

    /// @notice Mapping from asset token to its configured Comet market.
    mapping(address => address) public assetToComet;

    /// @notice MT token address (burned on redemption).
    address public mtToken;

    /// @notice Agent address for off-chain orchestrated actions (also captured in role).
    address public agent;

    /// @notice The three lifecycle phases for the vault.
    enum Phase {
        LOCKED,
        CONSOLIDATION,
        REDEMPTION
    }

    // --------------------
    // Events
    // --------------------
    event SwapExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event CometSupplied(address comet, address asset, uint256 amount);
    event CometWithdrawn(address comet, address asset, uint256 amount);
    event CompClaimed(address comet, address to, uint256 amount);
    event Redeemed(address account, address to, uint256 mtBurned, uint256 wethOut);
    event AllowedAssetSet(address token, bool allowed);
    event AllowedCometSet(address comet, bool allowed);
    event AgentSet(address agent);
    event AssetCometSet(address asset, address comet);

    // --------------------
    // Modifiers
    // --------------------
    modifier onlyAgentOrOwner() {
        if (!(hasRole(AGENT_ROLE, msg.sender) || msg.sender == owner())) {
            revert VaultManager__InvalidAddress();
        }
        _;
    }

    // --------------------
    // Constructor
    // --------------------
    /// @param _usdc USDC token address
    /// @param _weth WETH token address
    /// @param _mtToken MT token address
    /// @param _uniswapV3Router Uniswap v3 SwapRouter address
    /// @param _cometRewards Compound v3 CometRewards address
    /// @param _agent Agent address to be granted AGENT_ROLE
    constructor(
        address _usdc,
        address _weth,
        address _mtToken,
        address _uniswapV3Router,
        address _cometRewards,
        address _agent
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _weth == address(0) || _uniswapV3Router == address(0) || _cometRewards == address(0))
        {
            revert VaultManager__InvalidAddress();
        }

        lockStart = block.timestamp;
        unlockTimestamp = lockStart + LOCK_DURATION;

        usdc = _usdc;
        weth = _weth;
        uniswapV3Router = _uniswapV3Router;
        cometRewards = _cometRewards;
        mtToken = _mtToken;
        agent = _agent;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (_agent != address(0)) {
            _grantRole(AGENT_ROLE, _agent);
        }
    }

    // --------------------
    // Uniswap v3 Integration
    // --------------------
    /// @notice Swap exact input amount via Uniswap v3 with the same signature as the router for tool compatibility.
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata paramsIn)
        external
        payable
        onlyAgentOrOwner
        whenNotPaused
        nonReentrant
        returns (uint256 amountOut)
    {
        if (paramsIn.amountIn == 0) revert VaultManager__AmountZero();
        if (!allowedAssets[paramsIn.tokenIn] || !allowedAssets[paramsIn.tokenOut]) {
            revert VaultManager__AssetNotAllowed();
        }

        Phase phase = getCurrentPhase();
        if (phase != Phase.LOCKED) {
            // After unlock, only allow consolidations into WETH
            if (paramsIn.tokenOut != weth) revert VaultManager__InvalidPhase();
        }

        // Approve router to pull tokenIn from this contract
        IERC20(paramsIn.tokenIn).approve(uniswapV3Router, 0);
        IERC20(paramsIn.tokenIn).approve(uniswapV3Router, paramsIn.amountIn);

        // Enforce recipient as this vault for safety regardless of provided value
        ISwapRouter.ExactInputSingleParams memory fwd = ISwapRouter.ExactInputSingleParams({
            tokenIn: paramsIn.tokenIn,
            tokenOut: paramsIn.tokenOut,
            fee: paramsIn.fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: paramsIn.amountIn,
            amountOutMinimum: paramsIn.amountOutMinimum,
            sqrtPriceLimitX96: paramsIn.sqrtPriceLimitX96
        });

        amountOut = ISwapRouter(uniswapV3Router).exactInputSingle(fwd);

        emit SwapExecuted(paramsIn.tokenIn, paramsIn.tokenOut, paramsIn.amountIn, amountOut);
    }

    // --------------------
    // Compound v3 Integration
    // --------------------
    /// @notice Supply an asset to its configured Comet market. Matches Comet's function name/signature.
    function supply(address asset, uint256 amount) external onlyAgentOrOwner whenNotPaused nonReentrant {
        address comet = assetToComet[asset];
        if (amount == 0) revert VaultManager__AmountZero();
        if (!allowedAssets[asset]) revert VaultManager__AssetNotAllowed();
        if (!allowedComets[comet] || comet == address(0)) revert VaultManager__CometNotAllowed();

        IERC20(asset).approve(comet, 0);
        IERC20(asset).approve(comet, amount);
        IComet(comet).supply(asset, amount);

        emit CometSupplied(comet, asset, amount);
    }

    /// @notice Withdraw an asset from its configured Comet market. Matches Comet's function name/signature.
    function withdraw(address asset, uint256 amount) external onlyAgentOrOwner whenNotPaused nonReentrant {
        address comet = assetToComet[asset];
        if (amount == 0) revert VaultManager__AmountZero();
        if (!allowedAssets[asset]) revert VaultManager__AssetNotAllowed();
        if (!allowedComets[comet] || comet == address(0)) revert VaultManager__CometNotAllowed();

        IComet(comet).withdraw(asset, amount);

        emit CometWithdrawn(comet, asset, amount);
    }

    /// @notice Claim COMP rewards for a given comet to a recipient.
    function claimComp(address comet, address to)
        external
        onlyAgentOrOwner
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (!allowedComets[comet]) revert VaultManager__CometNotAllowed();
        if (to == address(0)) revert VaultManager__InvalidAddress();

        uint256 claimed = ICometRewards(cometRewards).claimTo(comet, to, true);
        emit CompClaimed(comet, to, claimed);
        return claimed;
    }

    // --------------------
    // Phase Management & Redemption
    // --------------------
    /// @notice Return current phase based on timestamp and consolidation status.
    function getCurrentPhase() public view returns (Phase) {
        if (block.timestamp < unlockTimestamp) {
            return Phase.LOCKED;
        }

        // Post-unlock: check if consolidated
        if (_isConsolidatedInternal()) {
            return Phase.REDEMPTION;
        }
        return Phase.CONSOLIDATION;
    }

    /// @notice Returns true if all non-WETH balances are zero across allowed assets.
    function isConsolidated() external view returns (bool) {
        return _isConsolidatedInternal();
    }

    function _isConsolidatedInternal() internal view returns (bool) {
        // Check all allowed non-WETH assets held directly
        uint256 assetCount = _assetList.length;
        for (uint256 i = 0; i < assetCount; i++) {
            address token = _assetList[i];
            if (token != weth && allowedAssets[token]) {
                if (IERC20(token).balanceOf(address(this)) > 0) {
                    return false;
                }
            }
        }

        // Ensure no open positions in any allowed Comet market
        uint256 cometCount = _cometList.length;
        for (uint256 j = 0; j < cometCount; j++) {
            address comet = _cometList[j];
            if (allowedComets[comet] && IComet(comet).balanceOf(address(this)) > 0) {
                return false;
            }
        }
        return true;
    }

    /// @notice Burns MT and transfers pro-rata WETH to `to`. Only during REDEMPTION phase.
    function redeemWETH(uint256 mtAmount, address to) external whenNotPaused nonReentrant {
        if (mtAmount == 0) revert VaultManager__AmountZero();
        if (to == address(0)) revert VaultManager__InvalidAddress();
        if (getCurrentPhase() != Phase.REDEMPTION) revert VaultManager__InvalidPhase();

        // Calculate pro-rata based on pre-burn total supply
        uint256 wethBal = IERC20(weth).balanceOf(address(this));
        uint256 ts = CompCommToken(mtToken).totalSupply();
        uint256 wethOut = (wethBal * mtAmount) / ts;

        // Burn MT from sender using Vault's burner role
        CompCommToken(mtToken).burnFrom(msg.sender, mtAmount);

        IERC20(weth).transfer(to, wethOut);

        emit Redeemed(msg.sender, to, mtAmount, wethOut);
    }

    // --------------------
    // Admin Functions
    // --------------------
    function setAllowedAsset(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert VaultManager__InvalidAddress();
        allowedAssets[token] = allowed;
        if (!_assetSeen[token]) {
            _assetSeen[token] = true;
            _assetList.push(token);
        }
        emit AllowedAssetSet(token, allowed);
    }

    function setAllowedComet(address comet, bool allowed) external onlyOwner {
        if (comet == address(0)) revert VaultManager__InvalidAddress();
        allowedComets[comet] = allowed;
        if (!_cometSeen[comet]) {
            _cometSeen[comet] = true;
            _cometList.push(comet);
        }
        emit AllowedCometSet(comet, allowed);
    }

    /// @notice Configure the Comet market for a given asset.
    function setAssetComet(address asset, address comet) external onlyOwner {
        if (asset == address(0) || comet == address(0)) revert VaultManager__InvalidAddress();
        if (!allowedAssets[asset]) revert VaultManager__AssetNotAllowed();
        if (!allowedComets[comet]) revert VaultManager__CometNotAllowed();
        assetToComet[asset] = comet;
        emit AssetCometSet(asset, comet);
    }

    function setAgent(address newAgent) external onlyOwner {
        if (newAgent == address(0)) revert VaultManager__InvalidAddress();
        if (agent != address(0)) {
            _revokeRole(AGENT_ROLE, agent);
        }
        agent = newAgent;
        _grantRole(AGENT_ROLE, newAgent);
        emit AgentSet(newAgent);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency sweep of tokens with phase restrictions.
    function sweep(address token, address to) external onlyOwner nonReentrant {
        if (to == address(0) || token == address(0)) revert VaultManager__InvalidAddress();

        Phase phase = getCurrentPhase();
        if (phase == Phase.REDEMPTION && token == weth) {
            revert VaultManager__SweepRestricted();
        }

        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, bal);
    }
}
