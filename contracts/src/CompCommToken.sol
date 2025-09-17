// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";

/// @title CompCommToken
/// @notice The governance and redemption token for the CompComm Portfolio system.
/// @dev Implements ERC20 with burnable functionality, role-based access control, and pausable
/// transfers.
contract CompCommToken is ERC20, ERC20Burnable, AccessControl, Pausable {
  /// @notice Thrown when attempting to mint to the zero address.
  error CompCommToken__InvalidMintAddress();

  /// @notice Thrown when attempting to burn from the zero address.
  error CompCommToken__InvalidBurnAddress();

  /// @notice Thrown when attempting to burn more tokens than the account has.
  error CompCommToken__InsufficientBalance();

  /// @notice Thrown when attempting to burn more tokens than allowed.
  error CompCommToken__InsufficientAllowance();

  /// @notice Role for minting new tokens (granted to MessageManager and PolicyManager).
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  /// @notice Role for burning tokens from accounts (granted to VaultManager for redemption).
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

  /// @notice Role for pausing/unpausing transfers.
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// @notice Emitted when tokens are minted.
  /// @param to The address that received the minted tokens.
  /// @param amount The amount of tokens minted.
  event TokensMinted(address indexed to, uint256 amount);

  /// @notice Emitted when tokens are burned from an account.
  /// @param account The account from which tokens were burned.
  /// @param amount The amount of tokens burned.
  event TokensBurned(address indexed account, uint256 amount);

  /// @notice Emitted when transfers are paused.
  event TransfersPaused(address account);

  /// @notice Emitted when transfers are unpaused.
  event TransfersUnpaused(address account);

  /// @notice Initializes the CompCommToken contract.
  /// @param _admin The address that will have admin role.
  constructor(address _admin) ERC20("CompComm Management Token", "MT") {
    if (_admin == address(0)) revert CompCommToken__InvalidMintAddress();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  /// @notice Mints new MT tokens to the specified address.
  /// @param to The address to mint tokens to.
  /// @param amount The amount of tokens to mint.
  /// @dev Only callable by addresses with MINTER_ROLE.
  function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
    if (to == address(0)) revert CompCommToken__InvalidMintAddress();

    _mint(to, amount);
    emit TokensMinted(to, amount);
  }

  /// @notice Burns MT tokens from the specified account.
  /// @param account The account to burn tokens from.
  /// @param amount The amount of tokens to burn.
  /// @dev Only callable by addresses with BURNER_ROLE.
  /// @dev Requires the caller to have allowance or BURNER_ROLE.
  function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
    if (account == address(0)) revert CompCommToken__InvalidBurnAddress();
    if (balanceOf(account) < amount) revert CompCommToken__InsufficientBalance();

    // Check if caller has sufficient allowance or is the account owner
    if (msg.sender != account) {
      uint256 currentAllowance = allowance(account, msg.sender);
      if (currentAllowance < amount) revert CompCommToken__InsufficientAllowance();

      // Reduce allowance
      _approve(account, msg.sender, currentAllowance - amount);
    }

    _burn(account, amount);
    emit TokensBurned(account, amount);
  }

  /// @notice Pauses all token transfers.
  /// @dev Only callable by addresses with PAUSER_ROLE.
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
    emit TransfersPaused(msg.sender);
  }

  /// @notice Unpauses all token transfers.
  /// @dev Only callable by addresses with PAUSER_ROLE.
  function unpause() external onlyRole(PAUSER_ROLE) {
    _unpause();
    emit TransfersUnpaused(msg.sender);
  }

  /// @notice Hook that is called before any transfer of tokens.
  /// @param from The address tokens are transferred from.
  /// @param to The address tokens are transferred to.
  /// @param value The amount of tokens to transfer.
  /// @dev Overrides the parent function to add pausable functionality.
  function _update(address from, address to, uint256 value) internal override whenNotPaused {
    super._update(from, to, value);
  }
}
