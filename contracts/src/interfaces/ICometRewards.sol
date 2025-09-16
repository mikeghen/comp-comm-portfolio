// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICometRewards {
    function claimTo(address comet, address to, bool shouldAccrue) external returns (uint256);
}


