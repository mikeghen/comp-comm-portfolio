// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DeployBaseImpl} from "./DeployBaseImpl.s.sol";

/// @title BaseNetworkDeploy
/// @notice Base mainnet configuration for deploying CompComm portfolio contracts
contract BaseNetworkDeploy is DeployBaseImpl {
  /// @dev Set Base mainnet addresses and then call parent setup to pull env configs.
  function setUp() public override {
    // ---- Base mainnet core addresses ----
    USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    WETH = 0x4200000000000000000000000000000000000006;

    // Uniswap v3 Router02 on Base
    UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    // Compound v3 CometRewards on Base
    COMET_REWARDS = 0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1;

    // Core comet markets
    COMET_USDC = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
    COMET_WETH = 0x46e6b214b524310239732D51387075E0e70970bf;

    // ---- Additional Base-specific assets ----
    address AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address COMET_AERO = 0x784efeB622244d2348d4F2522f8860B96fbEcE89;

    _addAdditionalAsset(AERO);
    _addAdditionalComet(COMET_AERO);
    _setAssetCometMapping(AERO, COMET_AERO);

    // Inherit env-driven actor configuration
    super.setUp();
  }

  function run() public override {
    super.run();
  }
}
