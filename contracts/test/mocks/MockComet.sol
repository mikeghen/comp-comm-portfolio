// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

/// @notice Minimal mock of Compound v3 Comet for testing.
contract MockComet {
    mapping(address => uint256) public balances;

    event Supplied(address indexed from, address indexed asset, uint256 amount);
    event Withdrawn(address indexed to, address indexed asset, uint256 amount);

    function supply(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Supplied(msg.sender, asset, amount);
    }

    function withdraw(address asset, uint256 amount) external {
        uint256 bal = balances[msg.sender];
        require(bal >= amount, "INSUFFICIENT_BAL");
        balances[msg.sender] = bal - amount;
        IERC20(asset).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, asset, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}
