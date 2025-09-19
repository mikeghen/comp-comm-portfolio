// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {BaseNetworkDeploy} from "../../script/BaseNetworkDeploy.s.sol";
import {ManagementToken} from "../../src/ManagementToken.sol";
import {CompCommPortfolio} from "../../src/CompCommPortfolio.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

/// @title BaseDeploymentIntegrationTest
/// @notice Integration test for Base mainnet deployment
/// @dev Tests deployment script and validates functionality
contract BaseDeploymentIntegrationTest is Test {
  BaseNetworkDeploy public deployScript;
  ManagementToken public managementToken;
  CompCommPortfolio public portfolio;
  
  address public admin = makeAddr("admin");
  address public dev = makeAddr("dev");  
  address public agent = makeAddr("agent");
  address public user = makeAddr("user");
  
  string constant INITIAL_PROMPT = "Initial investment policy for the CompComm Portfolio system";

  function setUp() public {
    // Set up environment variables for the deployment
    vm.setEnv("ADMIN_ADDRESS", vm.toString(admin));
    vm.setEnv("DEV_ADDRESS", vm.toString(dev));
    vm.setEnv("AGENT_ADDRESS", vm.toString(agent));
    vm.setEnv("INITIAL_PROMPT", INITIAL_PROMPT);
    
    // Create deployment script
    deployScript = new BaseNetworkDeploy();
  }

  /// @notice Tests the complete deployment flow
  function test_DeploymentFlow() public {
    // Run the deployment
    (managementToken, portfolio) = deployScript.run();
    
    // Verify contracts are deployed
    assertNotEq(address(managementToken), address(0), "ManagementToken not deployed");
    assertNotEq(address(portfolio), address(0), "Portfolio not deployed");
    
    // Verify token configuration
    assertEq(managementToken.name(), "CompComm Management Token");
    assertEq(managementToken.symbol(), "MT");
    assertEq(managementToken.decimals(), 18);
    
    // Verify initial supply is zero
    assertEq(managementToken.totalSupply(), 0);
  }

  /// @notice Tests admin role configuration
  function test_AdminRoleConfiguration() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Verify admin has DEFAULT_ADMIN_ROLE on token
    assertTrue(
      managementToken.hasRole(managementToken.DEFAULT_ADMIN_ROLE(), admin),
      "Admin should have DEFAULT_ADMIN_ROLE"
    );
    
    // Verify portfolio is owner of VaultManager functions
    assertEq(portfolio.owner(), admin, "Admin should own portfolio");
    
    // Verify portfolio has MINTER_ROLE
    assertTrue(
      managementToken.hasRole(managementToken.MINTER_ROLE(), address(portfolio)),
      "Portfolio should have MINTER_ROLE"
    );
    
    // Verify portfolio has BURNER_ROLE  
    assertTrue(
      managementToken.hasRole(managementToken.BURNER_ROLE(), address(portfolio)),
      "Portfolio should have BURNER_ROLE"
    );
  }

  /// @notice Tests agent role configuration
  function test_AgentRoleConfiguration() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Verify agent has AGENT_ROLE
    assertTrue(
      portfolio.hasRole(portfolio.AGENT_ROLE(), agent),
      "Agent should have AGENT_ROLE"
    );
  }

  /// @notice Tests allowlist configuration
  function test_AllowlistConfiguration() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Base mainnet addresses
    address BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address BASE_WETH = 0x4200000000000000000000000000000000000006;
    address BASE_AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address BASE_CUSDC_V3 = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address BASE_CWETH_V3 = 0x46e6b214b524310239732D51387075E0e70970bf;
    
    // Verify allowed assets
    assertTrue(portfolio.allowedAssets(BASE_USDC), "USDC should be allowed");
    assertTrue(portfolio.allowedAssets(BASE_WETH), "WETH should be allowed");
    assertTrue(portfolio.allowedAssets(BASE_AERO), "AERO should be allowed");
    
    // Verify allowed Comets
    assertTrue(portfolio.allowedComets(BASE_CUSDC_V3), "cUSDCv3 should be allowed");
    assertTrue(portfolio.allowedComets(BASE_CWETH_V3), "cWETHv3 should be allowed");
  }

  /// @notice Tests policy manager initialization
  function test_PolicyManagerInitialization() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Verify initial prompt is set
    assertEq(portfolio.prompt(), INITIAL_PROMPT, "Initial prompt should be set");
    assertEq(portfolio.promptVersion(), 1, "Initial prompt version should be 1");
    
    // Verify dev address is set
    assertEq(portfolio.DEV(), dev, "Dev address should be set correctly");
  }

  /// @notice Tests message manager functionality
  function test_MessageManagerFunctionality() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Verify constants
    assertEq(portfolio.MESSAGE_PRICE_USDC(), 10_000_000, "Message cost should be 10 USDC");
    assertEq(portfolio.MT_PER_MESSAGE_USER(), 1 ether, "MT per message should be 1.0");
    assertEq(portfolio.DEV_BPS(), 2000, "Dev BPS should be 2000 (20%)");
  }

  /// @notice Tests vault manager timelock configuration  
  function test_VaultManagerTimelock() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Verify timelock configuration
    assertEq(portfolio.LOCK_DURATION(), 46_656_000, "Lock duration should be 18 months");
    assertGt(portfolio.LOCK_START(), 0, "Lock start should be set");
    assertEq(
      portfolio.UNLOCK_TIMESTAMP(), 
      portfolio.LOCK_START() + portfolio.LOCK_DURATION(),
      "Unlock timestamp should be calculated correctly"
    );
  }

  /// @notice Tests token minting functionality (simulated)
  function test_TokenMintingFunctionality() public {
    (managementToken, portfolio) = deployScript.run();
    
    // Simulate admin granting roles for testing
    vm.startPrank(admin);
    
    // Test that portfolio can mint tokens
    uint256 mintAmount = 1 ether;
    portfolio.mint(user, mintAmount);
    
    assertEq(managementToken.balanceOf(user), mintAmount, "User should receive minted tokens");
    assertEq(managementToken.totalSupply(), mintAmount, "Total supply should increase");
    
    vm.stopPrank();
  }

  /// @notice Tests token burning functionality (simulated)
  function test_TokenBurningFunctionality() public {
    (managementToken, portfolio) = deployScript.run();
    
    vm.startPrank(admin);
    
    // First mint some tokens
    uint256 mintAmount = 1 ether;
    portfolio.mint(user, mintAmount);
    
    // Grant approval for burning
    vm.stopPrank();
    vm.startPrank(user);
    managementToken.approve(address(portfolio), mintAmount);
    vm.stopPrank();
    
    vm.startPrank(admin);
    
    // Test that portfolio can burn tokens
    uint256 burnAmount = 0.5 ether;
    portfolio.burnFrom(user, burnAmount);
    
    assertEq(
      managementToken.balanceOf(user), 
      mintAmount - burnAmount, 
      "User balance should decrease after burn"
    );
    assertEq(
      managementToken.totalSupply(), 
      mintAmount - burnAmount, 
      "Total supply should decrease after burn"
    );
    
    vm.stopPrank();
  }

  /// @notice Tests admin control functions
  function test_AdminControlFunctions() public {
    (managementToken, portfolio) = deployScript.run();
    
    vm.startPrank(admin);
    
    // Test pausing
    portfolio.pause();
    assertTrue(portfolio.paused(), "Portfolio should be paused");
    
    // Test unpausing
    portfolio.unpause();
    assertFalse(portfolio.paused(), "Portfolio should be unpaused");
    
    // Test asset configuration
    address newAsset = makeAddr("newAsset");
    portfolio.configureAllowedAsset(newAsset, true);
    assertTrue(portfolio.allowedAssets(newAsset), "New asset should be allowed");
    
    // Test Comet configuration  
    address newComet = makeAddr("newComet");
    portfolio.configureAllowedComet(newComet, true);
    assertTrue(portfolio.allowedComets(newComet), "New Comet should be allowed");
    
    vm.stopPrank();
  }

  /// @notice Tests that non-admin cannot perform restricted actions
  function test_AccessControlRestrictions() public {
    (managementToken, portfolio) = deployScript.run();
    
    vm.startPrank(user);
    
    // Test that user cannot pause
    vm.expectRevert();
    portfolio.pause();
    
    // Test that user cannot configure assets
    vm.expectRevert();
    portfolio.configureAllowedAsset(makeAddr("asset"), true);
    
    // Test that user cannot configure Comets
    vm.expectRevert();
    portfolio.configureAllowedComet(makeAddr("comet"), true);
    
    // Test that user cannot mint directly
    vm.expectRevert();
    portfolio.mint(user, 1 ether);
    
    vm.stopPrank();
  }
}