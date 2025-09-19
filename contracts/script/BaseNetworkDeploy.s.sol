// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DeployBaseImpl} from "./DeployBaseImpl.s.sol";

/// @title BaseNetworkDeploy
/// @notice Base mainnet specific deployment configuration for CompComm Portfolio
/// @dev Implements network-specific addresses and configuration for Base mainnet
contract BaseNetworkDeploy is DeployBaseImpl {
  /// @notice Base mainnet USDC address
  address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  
  /// @notice Base mainnet WETH address
  address constant BASE_WETH = 0x4200000000000000000000000000000000000006;
  
  /// @notice Base mainnet Uniswap V3 Router address
  address constant BASE_UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
  
  /// @notice Base mainnet Compound V3 CometRewards address
  /// @dev This would need to be updated with the actual Base CometRewards address
  address constant BASE_COMET_REWARDS = 0x123456789012345678901234567890123456789A; // Placeholder
  
  /// @notice Example allowed assets for Base mainnet
  address constant BASE_AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // Aerodrome
  address constant BASE_SUSDC = 0x3FbC4C6b30fb0db3fA3DE8060B985052B48dED2; // sUSDC placeholder
  
  /// @notice Example allowed Comets for Base mainnet  
  address constant BASE_CUSDC_V3 = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf; // cUSDCv3
  address constant BASE_CWETH_V3 = 0x46e6b214b524310239732D51387075E0e70970bf; // cWETHv3
  address constant BASE_CAERO_V3 = 0x123456789012345678901234567890123456789B; // cAEROv3 placeholder
  address constant BASE_SSUSDC_V3 = 0x123456789012345678901234567890123456789C; // sSUSDv3 placeholder

  /// @notice Returns the base configuration for Base mainnet
  /// @return The base configuration
  function _baseConfiguration() internal pure override returns (BaseConfiguration memory) {
    return BaseConfiguration({
      admin: vm.envAddress("ADMIN_ADDRESS")
    });
  }

  /// @notice Returns the portfolio configuration for Base mainnet
  /// @return The portfolio configuration
  function _portfolioConfiguration() internal view override returns (PortfolioConfiguration memory) {
    return PortfolioConfiguration({
      usdc: BASE_USDC,
      weth: BASE_WETH,
      uniswapV3Router: BASE_UNISWAP_V3_ROUTER,
      cometRewards: BASE_COMET_REWARDS,
      dev: vm.envAddress("DEV_ADDRESS"),
      agent: vm.envAddress("AGENT_ADDRESS"),
      initialPrompt: vm.envString("INITIAL_PROMPT")
    });
  }

  /// @notice Configures Base mainnet specific allowlists
  /// @param _portfolio The CompCommPortfolio contract
  function _configureAllowlists(CompCommPortfolio _portfolio) internal override {
    console.log("Configuring Base mainnet allowlists...");
    
    // Configure allowed assets
    console.log("Setting allowed assets...");
    _portfolio.configureAllowedAsset(BASE_USDC, true);
    _portfolio.configureAllowedAsset(BASE_WETH, true);
    _portfolio.configureAllowedAsset(BASE_AERO, true);
    _portfolio.configureAllowedAsset(BASE_SUSDC, true);
    
    // Configure allowed Comets
    console.log("Setting allowed Comets...");
    _portfolio.configureAllowedComet(BASE_CUSDC_V3, true);
    _portfolio.configureAllowedComet(BASE_CWETH_V3, true);
    _portfolio.configureAllowedComet(BASE_CAERO_V3, true);
    _portfolio.configureAllowedComet(BASE_SSUSDC_V3, true);
    
    // Configure asset to Comet mappings (if needed)
    console.log("Configuring asset-to-Comet mappings...");
    _portfolio.setAssetComet(BASE_USDC, BASE_CUSDC_V3);
    _portfolio.setAssetComet(BASE_WETH, BASE_CWETH_V3);
    _portfolio.setAssetComet(BASE_AERO, BASE_CAERO_V3);
    _portfolio.setAssetComet(BASE_SUSDC, BASE_SSUSDC_V3);
    
    console.log("Base mainnet allowlists configured");
  }
}