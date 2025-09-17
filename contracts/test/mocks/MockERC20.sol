// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Mock ERC20 token for testing purposes.
contract MockERC20 is ERC20 {
  uint8 private _decimals;

  constructor(string memory _name, string memory _symbol, uint8 _decimalsValue)
    ERC20(_name, _symbol)
  {
    _decimals = _decimalsValue;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
