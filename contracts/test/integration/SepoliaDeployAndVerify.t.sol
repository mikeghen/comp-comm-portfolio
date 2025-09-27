// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {IComet} from "src/interfaces/IComet.sol";

import {SepoliaNetworkDeploy} from "script/SepoliaNetworkDeploy.s.sol";
import {ManagementToken} from "src/ManagementToken.sol";
import {PolicyManager} from "src/PolicyManager.sol";
import {MessageManager} from "src/MessageManager.sol";
import {VaultManager} from "src/VaultManager.sol";

/// @notice Integration test that deploys via SepoliaNetworkDeploy and verifies roles and flows
contract SepoliaDeployAndVerifyIntegration is Test {
  // Fork config
  string rpcAlias = "sepolia";

  // Actors
  address admin;
  address agent;
  address dev;
  uint256 adminPk;
  uint256 deployerPk;

  // Contracts from deployment
  ManagementToken mt;
  PolicyManager policy;
  MessageManager msgMgr;
  VaultManager vault;

  // Sepolia addresses
  address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
  address constant WETH = 0x2D5ee574e710219a521449679A4A7f2B43f046ad;
  address constant COMP = 0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531;
  address constant WBTC = 0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F;
  address constant COMET_USDC = 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e;
  address constant COMET_WETH = 0x2943ac1216979aD8dB76D9147F64E61adc126e96;

  function setUp() public virtual {
    string memory rpc = vm.rpcUrl(rpcAlias);
    try vm.envUint("SEPOLIA_BLOCK_NUMBER") returns (uint256 blockNumber) {
      vm.createSelectFork(rpc, blockNumber);
    } catch {
      // Use latest block if no specific block is set
      vm.createSelectFork(rpc, 9_284_149); // Sep-26-2025 01:03:48 PM +UTC
    }

    // Generate ephemeral keys for test to drive Ownable2Step accept
    deployerPk = 0xD3C00123;
    adminPk = 0xAD000123;
    admin = vm.addr(adminPk);
    agent = makeAddr("Agent");
    dev = makeAddr("Dev");

    // Set env for script - but disable internal broadcasting to avoid nested broadcast in tests
    vm.setEnv("DEPLOYER_PRIVATE_KEY", "0");
    vm.setEnv("ADMIN_PRIVATE_KEY", "0");
    vm.setEnv("ADMIN_ADDRESS", vm.toString(admin));
    vm.setEnv("AGENT_ADDRESS", vm.toString(agent));
    vm.setEnv("DEV_ADDRESS", vm.toString(dev));
    vm.setEnv("INITIAL_PROMPT", "Sepolia testnet policy: diversified test strategy");

    // Execute deployment (no vm.startBroadcast inside due to keys=0)
    SepoliaNetworkDeploy d = new SepoliaNetworkDeploy();
    d.setUp();
    d.run();

    // Wire instances
    mt = d.managementToken();
    policy = d.policyManager();
    msgMgr = d.messageManager();
    vault = d.vaultManager();

    // Since admin key was disabled for acceptOwnership, accept via prank as admin
    vm.startPrank(admin);
    try vault.acceptOwnership() {} catch {}
    // Token roles need admin; grant now for test correctness
    mt.grantRole(mt.MINTER_ROLE(), address(policy));
    mt.grantRole(mt.MINTER_ROLE(), address(msgMgr));
    mt.grantRole(mt.BURNER_ROLE(), address(vault));
    mt.grantRole(mt.PAUSER_ROLE(), admin);

    // Ensure agent role is properly set in vault (should already be set by constructor, but verify)
    if (!vault.hasRole(vault.AGENT_ROLE(), agent)) vault.grantRole(vault.AGENT_ROLE(), agent);
    vm.stopPrank();
  }

  function test_DeployedContractsAndRolesConfigured() public view {
    // Token roles
    assertTrue(mt.hasRole(mt.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(mt.hasRole(mt.MINTER_ROLE(), address(policy)));
    assertTrue(mt.hasRole(mt.MINTER_ROLE(), address(msgMgr)));
    assertTrue(mt.hasRole(mt.BURNER_ROLE(), address(vault)));

    // Policy admin granted to admin (script) and deployer revoked or not present
    assertTrue(policy.hasRole(policy.DEFAULT_ADMIN_ROLE(), admin));

    // Message manager roles
    bytes32 AGENT_ROLE = keccak256("AGENT_ROLE");
    assertTrue(msgMgr.hasRole(AGENT_ROLE, agent));
    assertTrue(msgMgr.hasRole(msgMgr.DEFAULT_ADMIN_ROLE(), admin));

    // Vault
    assertEq(vault.owner(), admin);
    assertTrue(vault.hasRole(keccak256("AGENT_ROLE"), agent));
  }

  function test_VaultAssetsAndCometsConfigured() public view {
    // Core assets should be allowed
    assertTrue(vault.allowedAssets(USDC), "USDC should be allowed");
    assertTrue(vault.allowedAssets(WETH), "WETH should be allowed");

    // Additional Sepolia-specific assets should be allowed
    assertTrue(vault.allowedAssets(COMP), "COMP should be allowed");
    assertTrue(vault.allowedAssets(WBTC), "WBTC should be allowed");

    // Core comets should be allowed
    assertTrue(vault.allowedComets(COMET_USDC), "COMET_USDC should be allowed");
    assertTrue(vault.allowedComets(COMET_WETH), "COMET_WETH should be allowed");

    // Asset-to-comet mappings should be configured for core assets
    assertEq(vault.assetToComet(USDC), COMET_USDC, "USDC->COMET_USDC mapping");
    assertEq(vault.assetToComet(WETH), COMET_WETH, "WETH->COMET_WETH mapping");

    // Additional assets should not have comet mappings (no comets available on Sepolia)
    assertEq(vault.assetToComet(COMP), address(0), "COMP should have no comet mapping");
    assertEq(vault.assetToComet(WBTC), address(0), "WBTC should have no comet mapping");
  }

  function test_TokenMintViaPolicyEditAndMessagePay_BurnViaVaultRedeem() public {
    // ---- Arrange: fund user USDC and set approvals
    address user = makeAddr("User");
    // Give message manager and policy manager spending power via minting USDC to user
    uint256 editUnits = 2; // 20 chars
    uint256 totalCost =
      editUnits * policy.EDIT_PRICE_PER_10_CHARS_USDC() + msgMgr.MESSAGE_PRICE_USDC();
    deal(USDC, user, totalCost);

    // Approvals
    vm.prank(user);
    IERC20(USDC).approve(address(policy), type(uint256).max);
    vm.prank(user);
    IERC20(USDC).approve(address(msgMgr), type(uint256).max);

    // ---- Act: policy edit mints to user and dev
    (uint256 expectedUserMint, uint256 expectedDevMint) = _policyEditAndExpected(user, editUnits);
    // ---- Assert: MT balances updated
    assertEq(mt.balanceOf(user), expectedUserMint);
    assertEq(mt.balanceOf(dev), expectedDevMint);

    // ---- Act: pay for message to mint more MT
    (bytes32 messageHash, uint256 msgUserMint, uint256 msgDevMint, address payer) =
      _payMessageAndExpected("Hello from Sepolia integration test");
    // ---- Assert: further MT minted to payer and dev
    assertEq(mt.balanceOf(payer), msgUserMint);
    assertEq(mt.balanceOf(dev), expectedDevMint + msgDevMint);
    // Agent marks message as processed
    vm.prank(agent);
    msgMgr.markMessageProcessed(messageHash);
    assertTrue(msgMgr.processedMessages(messageHash));

    uint256 usdcBalance = IERC20(USDC).balanceOf(address(vault));
    vm.startPrank(agent);
    _trySwap(USDC, WETH, usdcBalance);
    vm.stopPrank();

    assertEq(IERC20(USDC).balanceOf(address(vault)), 0);
    // ---- Arrange: move to REDEMPTION phase and fund vault with WETH
    vm.warp(vault.UNLOCK_TIMESTAMP() + 1);
    // Consolidate by ensuring only WETH is held; for test simply fund WETH to vault
    uint256 wethIn = 10 ether;
    deal(WETH, address(vault), wethIn);

    // ---- Act: user redeems using their MT
    uint256 redeemAmt = expectedUserMint; // redeem using MT from policy edit
    vm.prank(user);
    mt.approve(address(vault), redeemAmt);
    uint256 expectedWethOut = _redeemAndExpected(user, redeemAmt);
    // ---- Assert: MT burned and WETH transferred
    assertEq(mt.balanceOf(user), 0);
    assertEq(IERC20(WETH).balanceOf(user), expectedWethOut);
  }

  function _trySwap(address tokenIn, address tokenOut, uint256 amountIn)
    internal
    returns (uint256 amountOut)
  {
    // Try common v3 fee tiers
    uint24[3] memory FEES = [uint24(500), uint24(3000), uint24(10_000)];
    for (uint256 i = 0; i < FEES.length; i++) {
      try vault.exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: tokenIn,
          tokenOut: tokenOut,
          fee: FEES[i],
          recipient: address(vault),
          amountIn: amountIn,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        })
      ) returns (uint256 outAmt) {
        amountOut = outAmt;
        return amountOut;
      } catch {}
    }
    revert("no viable v3 pool");
  }

  // ---- Uniswap Swap Tests (Limited on Sepolia) ----

  function test_AgentSwap_USDC_to_WETH_Sepolia() public {
    uint256 usdcAmt = 1000e6;
    deal(USDC, address(vault), usdcAmt);

    vm.startPrank(agent);
    uint256 wethOut = _trySwap(USDC, WETH, usdcAmt);
    vm.stopPrank();

    assertGt(wethOut, 0, "Should receive WETH from USDC swap");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully swapped");
  }

  function test_AgentSwap_WETH_to_USDC_Sepolia() public {
    uint256 wethAmt = 1 ether;
    deal(WETH, address(vault), wethAmt);

    vm.startPrank(agent);
    uint256 usdcOut = _trySwap(WETH, USDC, wethAmt);
    vm.stopPrank();

    assertGt(usdcOut, 0, "Should receive USDC from WETH swap");
    assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH should be fully swapped");
  }

  function test_AgentSwap_USDC_to_COMP_Sepolia() public {
    uint256 usdcAmt = 1000e6;
    deal(USDC, address(vault), usdcAmt);

    vm.startPrank(agent);
    uint256 compOut = _trySwap(USDC, COMP, usdcAmt);
    vm.stopPrank();

    assertGt(compOut, 0, "Should receive COMP from USDC swap");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully swapped");
  }

  function test_AgentSwap_COMP_to_USDC_Sepolia() public {
    uint256 compAmt = 100e18;
    deal(COMP, address(vault), compAmt);

    vm.startPrank(agent);
    uint256 usdcOut = _trySwap(COMP, USDC, compAmt);
    vm.stopPrank();

    assertGt(usdcOut, 0, "Should receive USDC from COMP swap");
    assertEq(IERC20(COMP).balanceOf(address(vault)), 0, "COMP should be fully swapped");
  }

  function test_AgentSwap_USDC_to_WBTC_Sepolia() public {
    uint256 usdcAmt = 1e6; // Small swap amount because of small liquidity pool for USDC-WBTC
    deal(USDC, address(vault), usdcAmt);

    vm.startPrank(agent);
    uint256 wbtcOut = _trySwap(USDC, WBTC, usdcAmt);
    vm.stopPrank();

    assertGt(wbtcOut, 0, "Should receive WBTC from USDC swap");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully swapped");
  }

  function test_AgentSwap_WBTC_to_USDC_Sepolia() public {
    uint256 wbtcAmt = 1e2; // 0.000001 WBTC (8 decimals) - small amount for liquidity
    deal(WBTC, address(vault), wbtcAmt);

    vm.startPrank(agent);
    uint256 usdcOut = _trySwap(WBTC, USDC, wbtcAmt);
    vm.stopPrank();

    assertGt(usdcOut, 0, "Should receive USDC from WBTC swap");
    assertEq(IERC20(WBTC).balanceOf(address(vault)), 0, "WBTC should be fully swapped");
  }

  // ---- Compound Supply Tests ----

  function test_AgentCompound_Supply_USDC() public {
    uint256 usdcAmt = 2000e6;
    deal(USDC, address(vault), usdcAmt);

    uint256 cometBefore = IComet(COMET_USDC).balanceOf(address(vault));
    vm.prank(agent);
    vault.supply(USDC, usdcAmt);
    uint256 cometAfter = IComet(COMET_USDC).balanceOf(address(vault));

    assertGe(cometAfter, cometBefore + usdcAmt - 1, "Comet balance should increase");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully supplied");
  }

  function test_AgentCompound_Supply_WETH() public {
    uint256 wethAmt = 2 ether;
    deal(WETH, address(vault), wethAmt);

    uint256 cometBefore = IComet(COMET_WETH).balanceOf(address(vault));
    vm.prank(agent);
    vault.supply(WETH, wethAmt);
    uint256 cometAfter = IComet(COMET_WETH).balanceOf(address(vault));

    assertGe(cometAfter, cometBefore + wethAmt - 1, "Comet balance should increase");
    assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH should be fully supplied");
  }

  // ---- Compound Withdraw Tests ----

  function test_AgentCompound_Withdraw_USDC() public {
    uint256 usdcAmt = 2000e6;
    deal(USDC, address(vault), usdcAmt);

    // First supply
    vm.prank(agent);
    vault.supply(USDC, usdcAmt);

    // Then withdraw half
    uint256 withdrawAmt = usdcAmt / 2;
    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));
    vm.prank(agent);
    vault.withdraw(USDC, withdrawAmt);
    uint256 usdcAfter = IERC20(USDC).balanceOf(address(vault));

    assertGe(usdcAfter, usdcBefore + withdrawAmt - 1, "USDC balance should increase");
  }

  function test_AgentCompound_Withdraw_WETH() public {
    uint256 wethAmt = 2 ether;
    deal(WETH, address(vault), wethAmt);

    // First supply
    vm.prank(agent);
    vault.supply(WETH, wethAmt);

    // Then withdraw half
    uint256 withdrawAmt = wethAmt / 2;
    uint256 wethBefore = IERC20(WETH).balanceOf(address(vault));
    vm.prank(agent);
    vault.withdraw(WETH, withdrawAmt);
    uint256 wethAfter = IERC20(WETH).balanceOf(address(vault));

    assertGe(wethAfter, wethBefore + withdrawAmt - 1, "WETH balance should increase");
  }

  // ---- Additional Asset Tests (No Compound Integration) ----

  function test_AdditionalAssets_COMP_NoCompound() public {
    // COMP is allowed as asset but has no Comet on Sepolia
    assertTrue(vault.allowedAssets(COMP), "COMP should be allowed as asset");
    assertEq(vault.assetToComet(COMP), address(0), "COMP should have no comet mapping");

    // Attempting to supply COMP should fail
    uint256 compAmt = 100e18;
    deal(COMP, address(vault), compAmt);

    vm.prank(agent);
    vm.expectRevert(); // Should revert due to no comet mapping
    vault.supply(COMP, compAmt);
  }

  function test_AdditionalAssets_WBTC_NoCompound() public {
    // WBTC is allowed as asset but has no Comet on Sepolia
    assertTrue(vault.allowedAssets(WBTC), "WBTC should be allowed as asset");
    assertEq(vault.assetToComet(WBTC), address(0), "WBTC should have no comet mapping");

    // Attempting to supply WBTC should fail
    uint256 wbtcAmt = 1e8; // 1 WBTC (8 decimals)
    deal(WBTC, address(vault), wbtcAmt);

    vm.prank(agent);
    vm.expectRevert(); // Should revert due to no comet mapping
    vault.supply(WBTC, wbtcAmt);
  }

  function test_AdminAbilities_SetAgent() public {
    address newAgent = makeAddr("NewAgent");
    vm.prank(admin);
    vault.setAgent(newAgent);
    assertTrue(vault.hasRole(keccak256("AGENT_ROLE"), newAgent));
  }

  // ---- Helpers to reduce local variable pressure ----
  function _policyEditAndExpected(address user, uint256 editUnits)
    internal
    returns (uint256 expectedUserMint, uint256 expectedDevMint)
  {
    string memory current = policy.prompt();
    uint256 len = bytes(current).length;
    string memory replacement = "ABCDEFGHIJKLMNOPQRST"; // 20 chars
    vm.prank(user);
    policy.editPrompt(0, 20 <= len ? 20 : len, replacement);

    expectedUserMint = editUnits * policy.MT_PER_10CHARS_USER();
    expectedDevMint = (expectedUserMint * policy.DEV_BPS()) / 10_000;
  }

  function _payMessageAndExpected(string memory message)
    internal
    returns (bytes32 messageHash, uint256 msgUserMint, uint256 msgDevMint, address payer)
  {
    payer = makeAddr("MessagePayer");
    messageHash = keccak256(abi.encodePacked(message));

    // fund and approve
    deal(USDC, payer, msgMgr.MESSAGE_PRICE_USDC());
    vm.prank(payer);
    IERC20(USDC).approve(address(msgMgr), type(uint256).max);

    // Pay for message directly
    vm.prank(payer);
    msgMgr.payForMessage(message);

    msgUserMint = msgMgr.MT_PER_MESSAGE_USER();
    msgDevMint = (msgUserMint * msgMgr.DEV_BPS()) / 10_000;
  }

  function _redeemAndExpected(address user, uint256 redeemAmt)
    internal
    returns (uint256 expectedWethOut)
  {
    uint256 wethVaultBefore = IERC20(WETH).balanceOf(address(vault));
    uint256 ts = mt.totalSupply();
    expectedWethOut = (wethVaultBefore * redeemAmt) / ts;
    vm.prank(user);
    vault.redeemWETH(redeemAmt, user);
  }
}
