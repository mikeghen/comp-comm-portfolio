// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DeployBaseImpl} from "./DeployBaseImpl.s.sol";

/// @title SepoliaNetworkDeploy
/// @notice ETH Sepolia testnet configuration for deploying CompComm portfolio contracts
contract SepoliaNetworkDeploy is DeployBaseImpl {
  /// @dev Set ETH Sepolia testnet addresses and then call parent setUp to pull env configs.
  function setUp() public override {
    // ---- ETH Sepolia testnet core addresses ----
    USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    WETH = 0x2D5ee574e710219a521449679A4A7f2B43f046ad;

    // Uniswap v3 Router02 on ETH Sepolia
    UNISWAP_V3_ROUTER = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;

    // Compound v3 CometRewards on ETH Sepolia
    COMET_REWARDS = 0x8bF5b658bdF0388E8b482ED51B14aef58f90abfD;

    // Core comet markets
    COMET_USDC = 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e;
    COMET_WETH = 0x2943ac1216979aD8dB76D9147F64E61adc126e96;

    // ---- Additional Sepolia-specific assets ----
    address COMP = 0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531;
    address WBTC = 0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F;

    _addAdditionalAsset(COMP);
    _addAdditionalAsset(WBTC);

    // Note: No additional comets available for COMP/WBTC on Sepolia testnet
    // So we don't add any additional comets or mappings

    // Inherit env-driven actor configuration
    super.setUp();
  }

  function run() public override {
    super.run();
  }
}
