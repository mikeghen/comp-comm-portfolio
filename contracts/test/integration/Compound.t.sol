// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {VaultManager} from "src/VaultManager.sol";
import {IComet} from "src/interfaces/IComet.sol";

/// @notice Base integration test that forks Base mainnet and wires real Compound v3 Comets
contract CompoundIntegrationBase is Test {
  // ---- Base mainnet addresses ----
  address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address constant WETH = 0x4200000000000000000000000000000000000006;
  address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

  address constant COMET_USDC = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
  address constant COMET_WETH = 0x46e6b214b524310239732D51387075E0e70970bf;
  address constant COMET_AERO = 0x784efeB622244d2348d4F2522f8860B96fbEcE89;

  // Not used in these tests, but required by constructor to be nonzero
  address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // canonical v3
    // router
  // Real CometRewards on Base mainnet
  address constant COMET_REWARDS = 0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1;
  // COMP token on Base mainnet
  address constant COMP = 0x9e1028F5F1D5eDE59748FFceE5532509976840E0;

  VaultManager vault;

  uint256 constant SUPPLY_AMOUNT = 1000e6;
  uint256 constant WITHDRAW_AMOUNT = 500e6;

  function setUp() public virtual {
    // Fork Base mainnet using the configured RPC alias "base"
    // Optionally pin a block by exporting BASE_BLOCK_NUMBER; otherwise use latest
    string memory rpc = vm.rpcUrl("base_mainnet");
    try vm.envUint("BASE_BLOCK_NUMBER") returns (uint256 blockNumber) {
      vm.createSelectFork(rpc, blockNumber);
    } catch {
      vm.createSelectFork(rpc, 35_676_715); // Sep-17-2025 08:59:37 PM
    }

    // Deploy the VaultManager owned by this test contract
    vault =
      new VaultManager(USDC, WETH, address(0), UNISWAP_V3_ROUTER, COMET_REWARDS, address(this));

    // Allowlist assets and comets, and configure mappings
    vault.setAllowedAsset(USDC, true);
    vault.setAllowedAsset(WETH, true);
    vault.setAllowedAsset(AERO, true);

    vault.setAllowedComet(COMET_USDC, true);
    vault.setAllowedComet(COMET_WETH, true);
    vault.setAllowedComet(COMET_AERO, true);

    vault.setAssetComet(USDC, COMET_USDC);
    vault.setAssetComet(WETH, COMET_WETH);
    vault.setAssetComet(AERO, COMET_AERO);
  }

  function _supplyAndAssert(address asset, address comet, uint256 amount) internal {
    // ---- Arrange
    // Give the Vault the asset balance directly on the fork
    deal(asset, address(vault), amount);
    uint256 vaultAssetBefore = IERC20(asset).balanceOf(address(vault));
    uint256 cometBefore = IComet(comet).balanceOf(address(vault));

    // ---- Act
    vault.supply(asset, amount);

    // ---- Assert
    uint256 vaultAssetAfter = IERC20(asset).balanceOf(address(vault));
    uint256 cometAfter = IComet(comet).balanceOf(address(vault));

    assertEq(vaultAssetBefore, amount, "pre: vault funded");
    assertEq(vaultAssetAfter, 0, "post: vault token debited");
    /// @dev Seems like immediately after supply, the comet balance is: amount - 1 wei
    assertGe(cometAfter, cometBefore + amount - 1, "comet balance increased");
  }

  function _withdrawAndAssert(address asset, address comet, uint256 amount) internal {
    // ---- Arrange
    uint256 vaultAssetBefore = IERC20(asset).balanceOf(address(vault));
    uint256 cometBefore = IComet(comet).balanceOf(address(vault));

    // ---- Act
    vault.withdraw(asset, amount);

    // ---- Assert
    uint256 vaultAssetAfter = IERC20(asset).balanceOf(address(vault));
    uint256 cometAfter = IComet(comet).balanceOf(address(vault));

    assertEq(vaultAssetAfter, vaultAssetBefore + amount, "vault token credited");
    // Allow tiny rounding drift in interest accrual between calls
    if (cometBefore >= amount) {
      assertGe(cometBefore, cometAfter + amount, "comet balance reduced by amount");
    }
  }
}

/// @notice Supply and withdraw USDC on the USDC Comet
contract SupplyWithdrawUSDC is CompoundIntegrationBase {
  function testFork_Supply_USDC() public {
    // ---- Act & Assert
    _supplyAndAssert(USDC, COMET_USDC, SUPPLY_AMOUNT);
  }

  function testFork_Withdraw_USDC() public {
    // ---- Arrange
    _supplyAndAssert(USDC, COMET_USDC, SUPPLY_AMOUNT);
    // ---- Act & Assert
    _withdrawAndAssert(USDC, COMET_USDC, WITHDRAW_AMOUNT);
  }
}

/// @notice Supply and withdraw WETH on the WETH Comet
contract SupplyWithdrawWETH is CompoundIntegrationBase {
  function testFork_Supply_WETH() public {
    // ---- Arrange
    // ---- Act & Assert
    _supplyAndAssert(WETH, COMET_WETH, SUPPLY_AMOUNT);
  }

  function testFork_Withdraw_WETH() public {
    // ---- Arrange
    _supplyAndAssert(WETH, COMET_WETH, SUPPLY_AMOUNT);
    // ---- Act & Assert
    _withdrawAndAssert(WETH, COMET_WETH, WITHDRAW_AMOUNT);
  }
}

/// @notice Supply and withdraw AERO on the AERO Comet
contract SupplyWithdrawAERO is CompoundIntegrationBase {
  function testFork_Supply_AERO() public {
    // ---- Arrange
    // ---- Act & Assert
    _supplyAndAssert(AERO, COMET_AERO, SUPPLY_AMOUNT);
  }

  function testFork_Withdraw_AERO() public {
    // ---- Arrange
    _supplyAndAssert(AERO, COMET_AERO, SUPPLY_AMOUNT);
    // ---- Act & Assert
    _withdrawAndAssert(AERO, COMET_AERO, WITHDRAW_AMOUNT);
  }
}

/// @dev TODO: Add test for claiming COMP rewards through CometRewards. This is not working yet.
// /// @notice Claim COMP rewards through CometRewards
// contract ClaimCompRewards is CompoundIntegrationBase {
//     function testFork_ClaimComp_ForUSDCComet() public {
//         // Ensure comet is allowed (done in setUp) and choose a recipient
//         address recipient = address(this);

//         // ---- Arrange: supply USDC to start accruing rewards
//         uint256 supplyAmount = 1_000e6; // 1,000 USDC
//         deal(USDC, address(vault), supplyAmount);
//         vault.supply(USDC, supplyAmount);

//         // Warp forward a few weeks so rewards accrue
//         vm.warp(block.timestamp + 30 days);

//         // ---- Act: claim rewards to recipient
//         uint256 beforeBal = IERC20(COMP).balanceOf(recipient);
//         uint256 claimed = vault.claimComp(COMET_USDC, recipient);
//         uint256 afterBal = IERC20(COMP).balanceOf(recipient);

//         // ---- Assert: claimed amount was transferred
//         assertEq(afterBal, beforeBal + claimed);
//         // Expect some non-zero accrual; if protocol has zero speed at this block this may be
// zero
//         assertGt(claimed, 0, "expected non-zero COMP accrual");
//     }
// }
