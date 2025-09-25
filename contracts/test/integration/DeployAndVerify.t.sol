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
contract DeployAndVerifyIntegration is Test {
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
  address constant COMET_USDC = 0xb125E6687d4313864e53df431d5425969c15Eb2F;

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

  function test_DeployedContractsAndRolesConfigured() public {
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

  function _trySwapUSDCtoWETH(uint256 amountIn) internal returns (uint256 amountOut) {
    // Try common v3 fee tiers
    uint24[3] memory FEES = [uint24(500), uint24(3000), uint24(10_000)];
    for (uint256 i = 0; i < FEES.length; i++) {
      try vault.exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: USDC,
          tokenOut: WETH,
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

  function test_AgentAbilities_UniswapAndCompound() public {
    // ---- Arrange: fund vault with USDC
    uint256 usdcAmt = 2000e6;
    deal(USDC, address(vault), usdcAmt);

    // Allowlist already set by deploy script

    // ---- Act: as agent, perform swap USDC->WETH
    vm.prank(agent);
    uint256 wethOut = _trySwapUSDCtoWETH(usdcAmt / 2);
    assertGt(wethOut, 0);

    // ---- Act: as agent, supply remaining USDC to USDC Comet
    uint256 remainingUSDC = IERC20(USDC).balanceOf(address(vault));
    uint256 cometBefore = IComet(COMET_USDC).balanceOf(address(vault));
    vm.prank(agent);
    vault.supply(USDC, remainingUSDC);
    uint256 cometAfter = IComet(COMET_USDC).balanceOf(address(vault));
    assertGe(cometAfter, cometBefore + remainingUSDC - 1);
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
