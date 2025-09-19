// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManagementToken} from "../src/ManagementToken.sol";
import {CompCommPortfolio} from "../src/CompCommPortfolio.sol";

/// @title DeployBaseImpl
/// @notice Base deployment implementation for the CompComm Portfolio system
/// @dev Follows the modular pattern from withtally/staker for extensible deployments
abstract contract DeployBaseImpl is Script {
  /// @notice The deployed ManagementToken contract (reference from portfolio)
  ManagementToken public managementToken;

  /// @notice The deployed CompCommPortfolio contract
  CompCommPortfolio public compCommPortfolio;

  /// @notice The address deploying the system
  address deployer;

  /// @notice Thrown if the initial admin is not the deployer
  error DeployBaseImpl__InvalidInitialAdmin();

  /// @notice Base configuration for the deployment
  /// @param admin The final admin of the management token contract
  struct BaseConfiguration {
    address admin;
  }

  /// @notice Portfolio-specific configuration for deployment
  /// @param usdc USDC token address
  /// @param weth WETH token address
  /// @param uniswapV3Router Uniswap v3 router address
  /// @param cometRewards Compound v3 rewards contract address
  /// @param dev Dev share receiver address
  /// @param agent Agent address for executing operations
  /// @param initialPrompt Initial investment policy prompt
  struct PortfolioConfiguration {
    address usdc;
    address weth;
    address uniswapV3Router;
    address cometRewards;
    address dev;
    address agent;
    string initialPrompt;
  }

  /// @notice Interface method that returns base configuration
  /// @return The base configuration for the system
  function _baseConfiguration() internal virtual returns (BaseConfiguration memory);

  /// @notice Interface method that returns portfolio-specific configuration
  /// @return The portfolio configuration for the system
  function _portfolioConfiguration() internal virtual returns (PortfolioConfiguration memory);

  /// @notice Deploys the CompCommPortfolio contract
  /// @param _config The portfolio configuration
  /// @return The deployed CompCommPortfolio
  function _deployPortfolio(PortfolioConfiguration memory _config) internal returns (CompCommPortfolio) {
    console.log("Deploying CompCommPortfolio...");
    CompCommPortfolio portfolio = new CompCommPortfolio(
      _config.usdc,
      _config.weth,
      _config.uniswapV3Router,
      _config.cometRewards,
      _config.dev,
      _config.agent,
      deployer, // admin
      _config.initialPrompt
    );
    console.log("CompCommPortfolio deployed at:", address(portfolio));
    return portfolio;
  }

  /// @notice Sets up roles and permissions
  /// @dev Roles are now set up automatically in the CompCommPortfolio constructor
  function _setupRoles(ManagementToken _token, CompCommPortfolio _portfolio) internal view {
    console.log("Roles set up automatically during deployment");
    
    // Verify roles were set correctly
    bool portfolioHasMinterRole = _token.hasRole(_token.MINTER_ROLE(), address(_portfolio.messageManager()));
    bool portfolioHasBurnerRole = _token.hasRole(_token.BURNER_ROLE(), address(_portfolio.vaultManager()));
    
    require(portfolioHasMinterRole, "MessageManager should have MINTER_ROLE");
    require(portfolioHasBurnerRole, "VaultManager should have BURNER_ROLE");
  }

  /// @notice Configures initial allowlists based on network
  /// @param _portfolio The CompCommPortfolio contract
  function _configureAllowlists(CompCommPortfolio _portfolio) internal virtual {
    // Override in network-specific implementations
  }

  /// @notice Transfers ownership to final admin
  /// @param _portfolio The CompCommPortfolio contract
  /// @param _baseConfig The base configuration
  function _transferOwnership(
    CompCommPortfolio _portfolio,
    BaseConfiguration memory _baseConfig
  ) internal {
    console.log("Transferring ownership to admin:", _baseConfig.admin);
    
    // Transfer admin role for ManagementToken
    ManagementToken token = _portfolio.managementToken();
    token.grantRole(token.DEFAULT_ADMIN_ROLE(), _baseConfig.admin);
    token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);
    
    // Transfer ownership of CompCommPortfolio (inherits from Ownable2Step)
    _portfolio.transferOwnership(_baseConfig.admin);
  }

  /// @notice Logs deployment summary
  /// @param _portfolio The CompCommPortfolio contract
  /// @param _config The portfolio configuration
  function _logDeploymentSummary(CompCommPortfolio _portfolio, PortfolioConfiguration memory _config) internal view {
    console.log("\n=== DEPLOYMENT SUMMARY ===");
    console.log("Network Chain ID:", block.chainid);
    console.log("Deployer:", deployer);
    console.log("USDC:", _config.usdc);
    console.log("WETH:", _config.weth);
    console.log("Uniswap V3 Router:", _config.uniswapV3Router);
    console.log("Comet Rewards:", _config.cometRewards);
    console.log("Dev:", _config.dev);
    console.log("Agent:", _config.agent);
    console.log("ManagementToken:", address(_portfolio.managementToken()));
    console.log("MessageManager:", address(_portfolio.messageManager()));
    console.log("PolicyManager:", address(_portfolio.policyManager()));
    console.log("VaultManager:", address(_portfolio.vaultManager()));
    console.log("CompCommPortfolio:", address(_portfolio));
    console.log("Initial Prompt Length:", bytes(_config.initialPrompt).length);
    console.log("=========================\n");

    // Verify role setup
    ManagementToken token = _portfolio.managementToken();
    bool messageManagerHasMinterRole = token.hasRole(
      token.MINTER_ROLE(), 
      address(_portfolio.messageManager())
    );
    console.log("MessageManager has MINTER_ROLE:", messageManagerHasMinterRole);

    bool policyManagerHasMinterRole = token.hasRole(
      token.MINTER_ROLE(), 
      address(_portfolio.policyManager())
    );
    console.log("PolicyManager has MINTER_ROLE:", policyManagerHasMinterRole);

    bool vaultManagerHasBurnerRole = token.hasRole(
      token.BURNER_ROLE(), 
      address(_portfolio.vaultManager())
    );
    console.log("VaultManager has BURNER_ROLE:", vaultManagerHasBurnerRole);
  }

  /// @notice Main deployment function
  /// @return The deployed CompCommPortfolio contract
  function run() public returns (CompCommPortfolio) {
    uint256 deployerPrivateKey = vm.envOr(
      "DEPLOYER_PRIVATE_KEY",
      uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
    );

    deployer = vm.rememberKey(deployerPrivateKey);
    vm.startBroadcast(deployer);

    // Get configurations
    BaseConfiguration memory baseConfig = _baseConfiguration();
    PortfolioConfiguration memory portfolioConfig = _portfolioConfiguration();

    // Deploy contracts
    compCommPortfolio = _deployPortfolio(portfolioConfig);
    
    // Get the deployed ManagementToken reference
    managementToken = compCommPortfolio.managementToken();

    // Setup system
    _setupRoles(managementToken, compCommPortfolio);
    _configureAllowlists(compCommPortfolio);
    _transferOwnership(compCommPortfolio, baseConfig);

    vm.stopBroadcast();

    // Log summary
    _logDeploymentSummary(compCommPortfolio, portfolioConfig);

    return compCommPortfolio;
  }
}