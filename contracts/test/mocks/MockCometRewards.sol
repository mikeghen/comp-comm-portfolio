// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal mock of Compound v3 CometRewards for testing.
contract MockCometRewards {
  mapping(address => uint256) public claimAmounts;

  event Claim(address indexed comet, address indexed src, bool shouldAccrue, uint256 amount);

  function setClaimAmount(address comet, uint256 amount) external {
    claimAmounts[comet] = amount;
  }

  function claim(address comet, address src, bool shouldAccrue) external returns (uint256) {
    uint256 amt = claimAmounts[comet];
    emit Claim(comet, src, shouldAccrue, amt);
    return amt;
  }
}
