// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {VaultManager} from "src/VaultManager.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {IComet} from "src/interfaces/IComet.sol";
import {ManagementToken} from "src/ManagementToken.sol";

contract LifecycleIntegrationTest is Test {
  // ---- Base mainnet addresses ----
  address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address constant WETH = 0x4200000000000000000000000000000000000006;
  address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

  address constant COMET_AERO = 0x784efeB622244d2348d4F2522f8860B96fbEcE89;

  // Uniswap V3 SwapRouter02 on Base mainnet
  address constant UNISWAP_V3_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

  // Placeholder (not used for this test) but required by constructor
  address constant COMET_REWARDS_DUMMY = 0x0000000000000000000000000000000000000001;

  VaultManager vault;
  ManagementToken mtToken;

  uint256 constant USDC_DEPOSIT = 1000e6; // 1,000 USDC
  uint24[3] FEES = [uint24(500), uint24(3000), uint24(10_000)];

  function setUp() public virtual {
    string memory rpc = vm.rpcUrl("base_mainnet");
    try vm.envUint("BASE_BLOCK_NUMBER") returns (uint256 blockNumber) {
      vm.createSelectFork(rpc, blockNumber);
    } catch {
      vm.createSelectFork(rpc, 35_676_715); // Sep-17-2025 08:59:37 PM
    }

    // Deploy MT token and grant roles
    mtToken = new ManagementToken(address(this));
    mtToken.grantRole(mtToken.MINTER_ROLE(), address(this));

    // Deploy vault with router02 and our MT token; owner/agent is this test contract
    vault = new VaultManager(
      USDC, WETH, address(mtToken), UNISWAP_V3_ROUTER_02, COMET_REWARDS_DUMMY, address(this)
    );

    // Allowlist assets and AERO comet
    vault.setAllowedAsset(USDC, true);
    vault.setAllowedAsset(WETH, true);
    vault.setAllowedAsset(AERO, true);
    vault.setAllowedComet(COMET_AERO, true);
    vault.setAssetComet(AERO, COMET_AERO);

    // Vault must be allowed to burn MT for redemption
    mtToken.grantRole(mtToken.BURNER_ROLE(), address(vault));
  }

  function _trySwap(address tokenIn, address tokenOut, uint256 amountIn)
    internal
    returns (uint256 amountOut)
  {
    ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: FEES[0],
      recipient: address(vault),
      amountIn: amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    for (uint256 i = 0; i < FEES.length; i++) {
      p.fee = FEES[i];
      try vault.exactInputSingle(p) returns (uint256 outAmt) {
        amountOut = outAmt;
        return amountOut;
      } catch {}
    }
    revert("no viable v3 pool");
  }

  function testFork_FullLifecycle_USDC_to_AERO_Comet_to_WETH_and_Redeem() public {
    // ---- Arrange: deposit 1,000 USDC into vault and mint 1,000 MT to user
    deal(USDC, address(vault), USDC_DEPOSIT);
    mtToken.mint(address(this), 1000e18);
    assertEq(mtToken.balanceOf(address(this)), 1000e18);

    // ---- Act: Swap USDC -> AERO during LOCKED phase
    uint256 aeroBefore = IERC20(AERO).balanceOf(address(vault));
    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));
    uint256 outAero = _trySwap(USDC, AERO, usdcBefore);
    uint256 aeroAfter = IERC20(AERO).balanceOf(address(vault));
    uint256 usdcAfter = IERC20(USDC).balanceOf(address(vault));
    assertEq(usdcBefore, USDC_DEPOSIT);
    assertEq(usdcAfter, 0);
    assertEq(aeroAfter, aeroBefore + outAero);

    // ---- Act: Supply all AERO into its Comet
    uint256 aeroBal = IERC20(AERO).balanceOf(address(vault));
    vault.supply(AERO, aeroBal);
    assertEq(IERC20(AERO).balanceOf(address(vault)), 0);
    uint256 cometBal = IComet(COMET_AERO).balanceOf(address(vault));
    // Allow small rounding on immediate accounting
    assertGe(cometBal, aeroBal - 1);

    // ---- Move to CONSOLIDATION phase (post-unlock, not consolidated)
    vm.warp(vault.UNLOCK_TIMESTAMP() + 1);
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.CONSOLIDATION));

    // ---- Act: Withdraw from Comet and swap AERO -> WETH (allowed post-unlock)
    // Withdraw full position
    uint256 cometBalNow = IComet(COMET_AERO).balanceOf(address(vault));
    vault.withdraw(AERO, cometBalNow);
    uint256 aeroPostWithdraw = IERC20(AERO).balanceOf(address(vault));
    assertGe(aeroPostWithdraw, cometBalNow - 1);

    // Swap all AERO to WETH using router v3 (post-unlock allows only to WETH)
    uint256 wethBefore = IERC20(WETH).balanceOf(address(vault));
    uint256 outWeth = _trySwap(AERO, WETH, aeroPostWithdraw);
    uint256 wethAfter = IERC20(WETH).balanceOf(address(vault));
    assertEq(wethAfter, wethBefore + outWeth);
    assertEq(IERC20(AERO).balanceOf(address(vault)), 0);

    // ---- Now consolidated (only WETH, no Comet positions) => REDEMPTION phase
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.REDEMPTION));

    // ---- Act: Redeem all WETH using MT
    uint256 totalSupply = mtToken.totalSupply();
    uint256 wethVaultBefore = IERC20(WETH).balanceOf(address(vault));
    uint256 redeemAmt = 1000e18;
    uint256 expectedWeth = (wethVaultBefore * redeemAmt) / totalSupply;

    // User approves vault to burn their MT
    mtToken.approve(address(vault), redeemAmt);
    vault.redeemWETH(redeemAmt, address(this));

    // ---- Assert: WETH transferred to user and MT burned
    assertEq(IERC20(WETH).balanceOf(address(this)), expectedWeth);
    assertEq(IERC20(WETH).balanceOf(address(vault)), wethVaultBefore - expectedWeth);
    assertEq(mtToken.balanceOf(address(this)), 0);
  }
}
