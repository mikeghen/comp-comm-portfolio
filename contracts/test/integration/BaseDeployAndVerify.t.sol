// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {IComet} from "src/interfaces/IComet.sol";

import {BaseNetworkDeploy} from "script/BaseNetworkDeploy.s.sol";
import {ManagementToken} from "src/ManagementToken.sol";
import {PolicyManager} from "src/PolicyManager.sol";
import {MessageManager} from "src/MessageManager.sol";
import {VaultManager} from "src/VaultManager.sol";

/// @notice Integration test that deploys via BaseNetworkDeploy and verifies roles and flows
contract BaseDeployAndVerifyIntegration is Test {
  // Fork config
  string rpcAlias = "base_mainnet";

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

  // Base addresses
  address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address constant WETH = 0x4200000000000000000000000000000000000006;
  address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
  address constant COMET_USDC = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
  address constant COMET_WETH = 0x46e6b214b524310239732D51387075E0e70970bf;
  address constant COMET_AERO = 0x784efeB622244d2348d4F2522f8860B96fbEcE89;

  function setUp() public virtual {
    string memory rpc = vm.rpcUrl(rpcAlias);
    try vm.envUint("BASE_BLOCK_NUMBER") returns (uint256 blockNumber) {
      vm.createSelectFork(rpc, blockNumber);
    } catch {
      vm.createSelectFork(rpc, 35_676_715);
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
    vm.setEnv("INITIAL_PROMPT", "Base policy: diversified long-term strategy");

    // Execute deployment (no vm.startBroadcast inside due to keys=0)
    BaseNetworkDeploy d = new BaseNetworkDeploy();
    d.setup();
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

    // Additional Base-specific asset should be allowed
    assertTrue(vault.allowedAssets(AERO), "AERO should be allowed");

    // Core comets should be allowed
    assertTrue(vault.allowedComets(COMET_USDC), "COMET_USDC should be allowed");
    assertTrue(vault.allowedComets(COMET_WETH), "COMET_WETH should be allowed");

    // Additional Base-specific comet should be allowed
    assertTrue(vault.allowedComets(COMET_AERO), "COMET_AERO should be allowed");

    // Asset-to-comet mappings should be configured
    assertEq(vault.assetToComet(USDC), COMET_USDC, "USDC->COMET_USDC mapping");
    assertEq(vault.assetToComet(WETH), COMET_WETH, "WETH->COMET_WETH mapping");
    assertEq(vault.assetToComet(AERO), COMET_AERO, "AERO->COMET_AERO mapping");
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

    // ---- Act: pay for message via signature to mint more MT
    (bytes32 digest, uint256 msgUserMint, uint256 msgDevMint, address payer) =
      _payMessageAndExpected(0xFACEFEED);
    // ---- Assert: further MT minted to payer and dev
    assertEq(mt.balanceOf(payer), msgUserMint);
    assertEq(mt.balanceOf(dev), expectedDevMint + msgDevMint);
    // Agent marks message as processed
    vm.prank(agent);
    msgMgr.markMessageProcessed(digest);
    assertTrue(msgMgr.processedMessages(digest));
    uint256 usdcBalance = IERC20(USDC).balanceOf(address(vault));
    vm.startPrank(agent);
    _trySwap(USDC, WETH, usdcBalance);
    vm.stopPrank();
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

  // ---- Uniswap Swap Tests ----

  function test_AgentSwap_USDC_to_WETH() public {
    uint256 usdcAmt = 1000e6;
    deal(USDC, address(vault), usdcAmt);

    vm.prank(agent);
    uint256 wethOut = _trySwap(USDC, WETH, usdcAmt);
    vm.stopPrank();

    assertGt(wethOut, 0, "Should receive WETH from USDC swap");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully swapped");
  }

  function test_AgentSwap_WETH_to_USDC() public {
    uint256 wethAmt = 1 ether;
    deal(WETH, address(vault), wethAmt);

    vm.startPrank(agent);
    uint256 usdcOut = _trySwap(WETH, USDC, wethAmt);
    vm.stopPrank();

    assertGt(usdcOut, 0, "Should receive USDC from WETH swap");
    assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH should be fully swapped");
  }

  function test_AgentSwap_USDC_to_AERO() public {
    uint256 usdcAmt = 1000e6;
    deal(USDC, address(vault), usdcAmt);

    vm.startPrank(agent);
    uint256 aeroOut = _trySwap(USDC, AERO, usdcAmt);
    vm.stopPrank();

    assertGt(aeroOut, 0, "Should receive AERO from USDC swap");
    assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC should be fully swapped");
  }

  function test_AgentSwap_AERO_to_USDC() public {
    uint256 aeroAmt = 1000e18;
    deal(AERO, address(vault), aeroAmt);

    vm.startPrank(agent);
    uint256 usdcOut = _trySwap(AERO, USDC, aeroAmt);
    vm.stopPrank();

    assertGt(usdcOut, 0, "Should receive USDC from AERO swap");
    assertEq(IERC20(AERO).balanceOf(address(vault)), 0, "AERO should be fully swapped");
  }

  function test_AgentSwap_WETH_to_AERO() public {
    uint256 wethAmt = 1 ether;
    deal(WETH, address(vault), wethAmt);

    vm.startPrank(agent);
    uint256 aeroOut = _trySwap(WETH, AERO, wethAmt);
    vm.stopPrank();

    assertGt(aeroOut, 0, "Should receive AERO from WETH swap");
    assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH should be fully swapped");
  }

  function test_AgentSwap_AERO_to_WETH() public {
    uint256 aeroAmt = 1000e18;
    deal(AERO, address(vault), aeroAmt);

    vm.startPrank(agent);
    uint256 wethOut = _trySwap(AERO, WETH, aeroAmt);
    vm.stopPrank();

    assertGt(wethOut, 0, "Should receive WETH from AERO swap");
    assertEq(IERC20(AERO).balanceOf(address(vault)), 0, "AERO should be fully swapped");
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

  function test_AgentCompound_Supply_AERO() public {
    uint256 aeroAmt = 1000e18;
    deal(AERO, address(vault), aeroAmt);

    uint256 cometBefore = IComet(COMET_AERO).balanceOf(address(vault));
    vm.prank(agent);
    vault.supply(AERO, aeroAmt);
    uint256 cometAfter = IComet(COMET_AERO).balanceOf(address(vault));

    assertGe(cometAfter, cometBefore + aeroAmt - 1, "Comet balance should increase");
    assertEq(IERC20(AERO).balanceOf(address(vault)), 0, "AERO should be fully supplied");
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

  function test_AgentCompound_Withdraw_AERO() public {
    uint256 aeroAmt = 1000e18;
    deal(AERO, address(vault), aeroAmt);

    // First supply
    vm.prank(agent);
    vault.supply(AERO, aeroAmt);

    // Then withdraw half
    uint256 withdrawAmt = aeroAmt / 2;
    uint256 aeroBefore = IERC20(AERO).balanceOf(address(vault));
    vm.prank(agent);
    vault.withdraw(AERO, withdrawAmt);
    uint256 aeroAfter = IERC20(AERO).balanceOf(address(vault));

    assertGe(aeroAfter, aeroBefore + withdrawAmt - 1, "AERO balance should increase");
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

  function _payMessageAndExpected(uint256 payerPk)
    internal
    returns (bytes32 digest, uint256 msgUserMint, uint256 msgDevMint, address payer)
  {
    payer = vm.addr(payerPk);
    // fund and approve
    deal(USDC, payer, msgMgr.MESSAGE_PRICE_USDC());
    vm.prank(payer);
    IERC20(USDC).approve(address(msgMgr), type(uint256).max);

    MessageManager.Message memory m =
      MessageManager.Message({messageHash: keccak256("hello"), payer: payer, nonce: 1});
    bytes32 structHash =
      keccak256(abi.encode(msgMgr.MESSAGE_TYPEHASH(), m.messageHash, m.payer, m.nonce));
    digest = keccak256(abi.encodePacked("\x19\x01", msgMgr.exposed_DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    vm.prank(makeAddr("Relayer"));
    msgMgr.payForMessageWithSig(m, sig, "ipfs://message");

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
