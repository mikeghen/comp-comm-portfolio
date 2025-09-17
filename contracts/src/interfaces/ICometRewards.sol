// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICometRewards {
  function claim(address comet, address src, bool shouldAccrue) external returns (uint256);
}
