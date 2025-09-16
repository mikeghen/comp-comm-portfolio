// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal mock of Compound v3 CometRewards for testing.
contract MockCometRewards {
    mapping(address => uint256) public claimAmounts;

    event ClaimTo(address indexed comet, address indexed to, bool shouldAccrue, uint256 amount);

    function setClaimAmount(address comet, uint256 amount) external {
        claimAmounts[comet] = amount;
    }

    function claimTo(address comet, address to, bool shouldAccrue) external returns (uint256) {
        uint256 amt = claimAmounts[comet];
        emit ClaimTo(comet, to, shouldAccrue, amt);
        return amt;
    }
}
