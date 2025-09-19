// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";
import {MessageManager} from "./MessageManager.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {VaultManager} from "./VaultManager.sol";
import {ManagementToken} from "./ManagementToken.sol";

/// @title CompCommPortfolio
/// @notice Main contract that coordinates the CompComm Portfolio system
/// @dev Uses composition pattern to avoid diamond inheritance issues
contract CompCommPortfolio is Ownable2Step, AccessControl, ReentrancyGuard, Pausable {
  /// @notice The MessageManager contract instance
  MessageManager public immutable messageManager;
  
  /// @notice The PolicyManager contract instance  
  PolicyManager public immutable policyManager;
  
  /// @notice The VaultManager contract instance
  VaultManager public immutable vaultManager;
  
  /// @notice The ManagementToken contract instance
  ManagementToken public immutable managementToken;

  /// @notice Role for agents that can execute operations
  bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

  /// @notice Emitted when the portfolio system is fully initialized
  event PortfolioInitialized(
    address indexed managementToken,
    address indexed messageManager,
    address indexed policyManager,
    address vaultManager,
    address agent,
    address dev
  );

  /// @notice Constructor that deploys and coordinates all system contracts
  /// @param _usdc USDC token address
  /// @param _weth WETH token address  
  /// @param _uniswapV3Router Uniswap v3 router address
  /// @param _cometRewards Compound v3 rewards contract address
  /// @param _dev Dev share receiver address
  /// @param _agent Agent address for executing operations
  /// @param _admin Admin address for access control
  /// @param _initialPrompt Initial investment policy prompt
  constructor(
    address _usdc,
    address _weth,
    address _uniswapV3Router,
    address _cometRewards,
    address _dev,
    address _agent,
    address _admin,
    string memory _initialPrompt
  ) Ownable(msg.sender) {
    // Deploy ManagementToken first
    managementToken = new ManagementToken(_admin);
    
    // Deploy manager contracts
    messageManager = new MessageManager(_usdc, address(managementToken), _dev, _agent, _admin);
    policyManager = new PolicyManager(_usdc, address(managementToken), _dev, _initialPrompt);
    vaultManager = new VaultManager(_usdc, _weth, address(managementToken), _uniswapV3Router, _cometRewards, _agent);
    
    // Setup roles
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(AGENT_ROLE, _agent);
    
    // Grant necessary token roles
    managementToken.grantRole(managementToken.MINTER_ROLE(), address(messageManager));
    managementToken.grantRole(managementToken.MINTER_ROLE(), address(policyManager));
    managementToken.grantRole(managementToken.BURNER_ROLE(), address(vaultManager));
    
    // Transfer ownership to admin
    _transferOwnership(_admin);

    emit PortfolioInitialized(
      address(managementToken),
      address(messageManager), 
      address(policyManager),
      address(vaultManager),
      _agent,
      _dev
    );
  }

  /// @notice Configure allowed assets (delegated to VaultManager)
  /// @param _asset Asset address to configure
  /// @param _allowed Whether the asset is allowed
  function configureAllowedAsset(address _asset, bool _allowed) external onlyOwner {
    vaultManager.setAllowedAsset(_asset, _allowed);
  }

  /// @notice Configure allowed Comets (delegated to VaultManager)
  /// @param _comet Comet address to configure
  /// @param _allowed Whether the comet is allowed
  function configureAllowedComet(address _comet, bool _allowed) external onlyOwner {
    vaultManager.setAllowedComet(_comet, _allowed);
  }

  /// @notice Configure asset to Comet mapping (delegated to VaultManager)
  /// @param _asset Asset address
  /// @param _comet Comet address
  function setAssetComet(address _asset, address _comet) external onlyOwner {
    vaultManager.setAssetComet(_asset, _comet);
  }

  /// @notice Pause the portfolio system
  function pause() external onlyOwner {
    _pause();
    vaultManager.pause();
  }

  /// @notice Unpause the portfolio system  
  function unpause() external onlyOwner {
    _unpause();
    vaultManager.unpause();
  }

  // Delegate functions for easier access (view functions)
  
  /// @notice Get investment policy prompt (delegated to PolicyManager)
  function prompt() external view returns (string memory) {
    return policyManager.prompt();
  }
  
  /// @notice Get policy version (delegated to PolicyManager)
  function promptVersion() external view returns (uint256) {
    return policyManager.promptVersion();
  }
  
  /// @notice Get dev address (delegated to PolicyManager)
  function DEV() external view returns (address) {
    return policyManager.DEV();
  }
  
  /// @notice Get message price (delegated to MessageManager)
  function MESSAGE_PRICE_USDC() external view returns (uint256) {
    return messageManager.MESSAGE_PRICE_USDC();
  }
  
  /// @notice Get MT per message (delegated to MessageManager)
  function MT_PER_MESSAGE_USER() external view returns (uint256) {
    return messageManager.MT_PER_MESSAGE_USER();
  }
  
  /// @notice Get dev BPS (delegated to MessageManager)
  function DEV_BPS() external view returns (uint256) {
    return messageManager.DEV_BPS();
  }
  
  /// @notice Get lock duration (delegated to VaultManager)
  function LOCK_DURATION() external view returns (uint256) {
    return vaultManager.LOCK_DURATION();
  }
  
  /// @notice Get lock start time (delegated to VaultManager)
  function LOCK_START() external view returns (uint256) {
    return vaultManager.LOCK_START();
  }
  
  /// @notice Get unlock timestamp (delegated to VaultManager)
  function UNLOCK_TIMESTAMP() external view returns (uint256) {
    return vaultManager.UNLOCK_TIMESTAMP();
  }
  
  /// @notice Check if asset is allowed (delegated to VaultManager)
  function allowedAssets(address _asset) external view returns (bool) {
    return vaultManager.allowedAssets(_asset);
  }
  
  /// @notice Check if Comet is allowed (delegated to VaultManager)
  function allowedComets(address _comet) external view returns (bool) {
    return vaultManager.allowedComets(_comet);
  }

  /// @notice Admin function to mint tokens (for testing/emergency)
  function mint(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    managementToken.mint(to, amount);
  }

  /// @notice Admin function to burn tokens (for testing/emergency)
  function burnFrom(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    managementToken.burnFrom(account, amount);
  }
}