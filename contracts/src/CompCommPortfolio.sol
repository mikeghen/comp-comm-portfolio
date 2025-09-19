// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";
import {MessageManager} from "./MessageManager.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {VaultManager} from "./VaultManager.sol";
import {ManagementToken} from "./ManagementToken.sol";

/// @title CompCommPortfolio
/// @notice Main contract that inherits from all manager contracts and coordinates the system
/// @dev Combines functionality from MessageManager, PolicyManager, and VaultManager
contract CompCommPortfolio is MessageManager, PolicyManager, VaultManager {
  /// @notice Emitted when the portfolio system is fully initialized
  event PortfolioInitialized(
    address indexed managementToken,
    address indexed agent,
    address indexed dev
  );

  /// @notice Constructor that initializes all manager contracts
  /// @param _usdc USDC token address
  /// @param _weth WETH token address  
  /// @param _mtToken Management token address
  /// @param _uniswapV3Router Uniswap v3 router address
  /// @param _cometRewards Compound v3 rewards contract address
  /// @param _dev Dev share receiver address
  /// @param _agent Agent address for executing operations
  /// @param _admin Admin address for access control
  /// @param _initialPrompt Initial investment policy prompt
  constructor(
    address _usdc,
    address _weth,
    address _mtToken,
    address _uniswapV3Router,
    address _cometRewards,
    address _dev,
    address _agent,
    address _admin,
    string memory _initialPrompt
  )
    MessageManager(_usdc, _mtToken, _dev, _agent, _admin)
    PolicyManager(_usdc, _mtToken, _dev, _initialPrompt)
    VaultManager(_usdc, _weth, _mtToken, _uniswapV3Router, _cometRewards, _agent)
  {
    // Initialize allowlists
    _initializeAllowlists();
    
    // Set up roles
    _setupRoles(_agent);

    emit PortfolioInitialized(_mtToken, _agent, _dev);
  }

  /// @notice Sets up initial allowed assets and Comets for Base mainnet
  /// @dev Called during construction to configure allowlists
  function _initializeAllowlists() internal {
    // Base mainnet addresses - these would be configured per network
    // WETH is already set in VaultManager constructor
    // USDC is already set in VaultManager constructor
    
    // Add other allowed assets for Base mainnet
    // Note: These addresses should be provided via constructor or configuration
    // For now, we'll set up the structure and allow configuration later
  }

  /// @notice Sets up roles for all manager contracts
  /// @param _agent Agent address to receive AGENT_ROLE
  /// @dev Grants necessary roles to enable contract functionality
  function _setupRoles(address _agent) internal {
    ManagementToken mtToken = ManagementToken(MT_TOKEN);
    
    // Grant MINTER_ROLE to MessageManager and PolicyManager components
    mtToken.grantRole(mtToken.MINTER_ROLE(), address(this));
    
    // Grant BURNER_ROLE to VaultManager component for redemptions
    mtToken.grantRole(mtToken.BURNER_ROLE(), address(this));
    
    // Grant AGENT_ROLE to agent address
    _grantRole(AGENT_ROLE, _agent);
  }

  /// @notice Allows owner to configure allowed assets after deployment
  /// @param _asset Asset address to configure
  /// @param _allowed Whether the asset is allowed
  function configureAllowedAsset(address _asset, bool _allowed) external onlyOwner {
    setAllowedAsset(_asset, _allowed);
  }

  /// @notice Allows owner to configure allowed Comets after deployment  
  /// @param _comet Comet address to configure
  /// @param _allowed Whether the comet is allowed
  function configureAllowedComet(address _comet, bool _allowed) external onlyOwner {
    setAllowedComet(_comet, _allowed);
  }

  /// @notice Forwards mint calls to the ManagementToken (for testing/admin use)
  /// @param to Address to mint tokens to
  /// @param amount Amount of tokens to mint
  function mint(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    ManagementToken(MT_TOKEN).mint(to, amount);
  }

  /// @notice Forwards burnFrom calls to the ManagementToken (for redemptions)
  /// @param account Account to burn tokens from
  /// @param amount Amount of tokens to burn
  function burnFrom(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    ManagementToken(MT_TOKEN).burnFrom(account, amount);
  }
}