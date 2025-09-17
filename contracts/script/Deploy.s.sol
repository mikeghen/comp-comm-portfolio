// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CompCommToken} from "../src/CompCommToken.sol";
import {PolicyManager} from "../src/PolicyManager.sol";

/// @title Deploy
/// @notice Deployment script for the CompComm Portfolio system contracts
/// @dev Deploys CompCommToken and PolicyManager with proper role configuration
contract Deploy is Script {
  /// @notice The deployed CompCommToken contract
  CompCommToken public compCommToken;

  /// @notice The deployed PolicyManager contract
  PolicyManager public policyManager;

  /// @notice Admin address for the CompCommToken (from environment)
  address public admin;

  /// @notice Dev share receiver address (from environment)
  address public dev;

  /// @notice USDC token address (from environment)
  address public usdc;

  /// @notice Initial investment policy prompt (from environment)
  string public initialPrompt;

  /// @notice Deployer private key (from environment)
  uint256 public deployerPrivateKey;

  /// @notice Main deployment function
  /// @dev Deploys both contracts and sets up proper roles
  function run() public {
    // Load configuration from environment
    _loadConfig();

    // Start broadcasting transactions
    vm.startBroadcast(deployerPrivateKey);

    // Deploy CompCommToken
    console.log("Deploying CompCommToken...");
    compCommToken = new CompCommToken(admin);
    console.log("CompCommToken deployed at:", address(compCommToken));

    // Deploy PolicyManager
    console.log("Deploying PolicyManager...");
    policyManager = new PolicyManager(usdc, address(compCommToken), dev, initialPrompt);
    console.log("PolicyManager deployed at:", address(policyManager));

    // Grant MINTER_ROLE to PolicyManager so it can mint tokens
    console.log("Granting MINTER_ROLE to PolicyManager...");
    compCommToken.grantRole(compCommToken.MINTER_ROLE(), address(policyManager));

    // Stop broadcasting
    vm.stopBroadcast();

    // Log deployment summary
    _logDeploymentSummary();
  }

  /// @notice Loads configuration from environment variables
  /// @dev Fails if required environment variables are not set
  function _loadConfig() internal {
    // Required addresses
    admin = vm.envAddress("ADMIN_ADDRESS");
    dev = vm.envAddress("DEV_ADDRESS");
    usdc = vm.envAddress("USDC_ADDRESS");

    // Required configuration
    initialPrompt = vm.envString("INITIAL_PROMPT");
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    // Validate addresses are not zero
    require(admin != address(0), "Deploy: ADMIN_ADDRESS cannot be zero");
    require(dev != address(0), "Deploy: DEV_ADDRESS cannot be zero");
    require(usdc != address(0), "Deploy: USDC_ADDRESS cannot be zero");
    require(bytes(initialPrompt).length > 0, "Deploy: INITIAL_PROMPT cannot be empty");
  }

  /// @notice Logs a summary of the deployment
  function _logDeploymentSummary() internal view {
    console.log("\n=== DEPLOYMENT SUMMARY ===");
    console.log("Network Chain ID:", block.chainid);
    console.log("Admin Address:", admin);
    console.log("Dev Address:", dev);
    console.log("USDC Address:", usdc);
    console.log("CompCommToken:", address(compCommToken));
    console.log("PolicyManager:", address(policyManager));
    console.log("Initial Prompt Length:", bytes(initialPrompt).length);
    console.log("=========================\n");

    // Verify role setup
    bool hasMinterRole = compCommToken.hasRole(compCommToken.MINTER_ROLE(), address(policyManager));
    console.log("PolicyManager has MINTER_ROLE:", hasMinterRole);

    bool adminHasAdminRole = compCommToken.hasRole(compCommToken.DEFAULT_ADMIN_ROLE(), admin);
    console.log("Admin has DEFAULT_ADMIN_ROLE:", adminHasAdminRole);
  }
}
