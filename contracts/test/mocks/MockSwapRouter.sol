// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MockSwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  event ExactInputSingleCalled(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint24 fee,
    address recipient,
    uint160 sqrtPriceLimitX96
  );

  uint256 public amountOutFactor = 2; // simple multiplier for predictable tests

  function setAmountOutFactor(uint256 _factor) external {
    amountOutFactor = _factor;
  }

  function exactInputSingle(ExactInputSingleParams calldata params)
    external
    returns (uint256 amountOut)
  {
    // Pull tokenIn from caller (the vault)
    IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

    // Compute deterministic amountOut
    amountOut = params.amountIn * amountOutFactor;

    // Mint tokenOut to recipient (tests use MockERC20 which exposes mint)
    MockERC20(params.tokenOut).mint(params.recipient, amountOut);

    emit ExactInputSingleCalled(
      params.tokenIn,
      params.tokenOut,
      params.amountIn,
      params.amountOutMinimum,
      params.fee,
      params.recipient,
      params.sqrtPriceLimitX96
    );
  }
}
