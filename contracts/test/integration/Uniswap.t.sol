// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {VaultManager} from "src/VaultManager.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";

/// @notice Base integration test that forks Base mainnet and wires real Uniswap v3 router
contract UniswapIntegrationBase is Test {
    // ---- Base mainnet addresses ----
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // Uniswap V3 SwapRouter02 on Base mainnet
    address constant UNISWAP_V3_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    // Placeholder (not used here) but required by constructor
    address constant COMET_REWARDS_DUMMY = 0x0000000000000000000000000000000000000001;

    VaultManager vault;

    // Standard fees to try in order
    uint24[3] FEES = [uint24(500), uint24(3000), uint24(10_000)];

    function setUp() public virtual {
        // Use same RPC aliasing approach as Compound integration
        string memory rpc = vm.rpcUrl("base_mainnet");
        try vm.envUint("BASE_BLOCK_NUMBER") returns (uint256 blockNumber) {
            vm.createSelectFork(rpc, blockNumber);
        } catch {
            vm.createSelectFork(rpc, 35676715); // Sep-17-2025 08:59:37 PM
        }

        // Owner is this test; pass router02
        vault = new VaultManager(USDC, WETH, address(0), UNISWAP_V3_ROUTER_02, COMET_REWARDS_DUMMY, address(this));

        // Allowlist the assets used for swaps
        vault.setAllowedAsset(USDC, true);
        vault.setAllowedAsset(WETH, true);
        vault.setAllowedAsset(AERO, true);
    }

    // External wrapper so we can try/catch swap attempts with different fee tiers
    function _executeSwap(ISwapRouter.ExactInputSingleParams memory params) external returns (uint256 amountOut) {
        amountOut = vault.exactInputSingle(params);
    }

    function _swapAndAssert(address tokenIn, address tokenOut, uint256 amountIn) internal {
        // ---- Arrange
        deal(tokenIn, address(vault), amountIn);
        uint256 inBefore = IERC20(tokenIn).balanceOf(address(vault));
        uint256 outBefore = IERC20(tokenOut).balanceOf(address(vault));

        // ---- Act: try common fee tiers until one succeeds
        uint256 amountOut;
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
            try this._executeSwap(p) returns (uint256 outAmt) {
                amountOut = outAmt;
                break;
            } catch {}
        }

        // ---- Assert
        require(amountOut > 0, "no viable v3 pool");

        uint256 inAfter = IERC20(tokenIn).balanceOf(address(vault));
        uint256 outAfter = IERC20(tokenOut).balanceOf(address(vault));

        // Exact input: tokenIn spent fully; tokenOut increased by amountOut
        assertEq(inBefore, amountIn, "pre: funded");
        assertEq(inAfter, 0, "post: tokenIn debited");
        assertEq(outAfter, outBefore + amountOut, "post: tokenOut credited");
    }
}

/// @notice Swap between USDC and WETH both directions
contract Swap_USDC_WETH is UniswapIntegrationBase {
    function testFork_Swap_USDC_to_WETH() public {
        _swapAndAssert(USDC, WETH, 1_000e6); // 1,000 USDC -> WETH
    }

    function testFork_Swap_WETH_to_USDC() public {
        _swapAndAssert(WETH, USDC, 0.01 ether); // 0.01 WETH -> USDC
    }
}

/// @notice Swap between USDC and AERO both directions
contract Swap_USDC_AERO is UniswapIntegrationBase {
    function testFork_Swap_USDC_to_AERO() public {
        _swapAndAssert(USDC, AERO, 1_000e6); // 1,000 USDC -> AERO
    }

    function testFork_Swap_AERO_to_USDC() public {
        _swapAndAssert(AERO, USDC, 1_000e18); // 1,000 AERO -> USDC
    }
}

/// @notice Swap between WETH and AERO both directions
contract Swap_WETH_AERO is UniswapIntegrationBase {
    function testFork_Swap_WETH_to_AERO() public {
        _swapAndAssert(WETH, AERO, 0.01 ether); // 0.01 WETH -> AERO
    }

    function testFork_Swap_AERO_to_WETH() public {
        _swapAndAssert(AERO, WETH, 1_000e18); // 1,000 AERO -> WETH
    }
}


