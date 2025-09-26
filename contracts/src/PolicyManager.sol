// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ManagementToken} from "./ManagementToken.sol";

/// @title PolicyManager
/// @notice Manages the on-chain investment policy with paid editing functionality.
/// @dev Handles USDC payments for policy edits and mints MT tokens to users and dev.
contract PolicyManager is AccessControl, ReentrancyGuard {
  /// @notice Thrown when the edit range is invalid.
  error PolicyManager__InvalidEditRange();

  /// @notice Thrown when the replacement length doesn't match the range.
  error PolicyManager__InvalidReplacementLength();

  /// @notice The investment policy stored as ASCII text.
  string public prompt;

  /// @notice Version counter that increments on each edit.
  uint256 public promptVersion;

  /// @notice USDC token address.
  address public immutable USDC;

  /// @notice MT token address.
  address public immutable MT_TOKEN;

  /// @notice Vault Address
  address public immutable VAULT;

  /// @notice Dev share receiver address.
  address public immutable DEV;

  /// @notice Edit price: 1 USDC per 10 characters (6 decimals).
  uint256 public constant EDIT_PRICE_PER_10_CHARS_USDC = 1_000_000;

  /// @notice MT minted per 10 characters: 0.1 MT (18 decimals).
  uint256 public constant MT_PER_10CHARS_USER = 100_000_000_000_000_000;

  /// @notice Dev share: 20% in basis points.
  uint256 public constant DEV_BPS = 2000;

  /// @notice Role for minting MT tokens.
  // @note Who is minter?
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  /// @notice Emitted when the prompt is edited.
  /// @param editor The address that made the edit.
  /// @param start The start index of the edit.
  /// @param end The end index of the edit.
  /// @param replacementLen The length of the replacement text.
  /// @param changed The number of 10-character units changed.
  /// @param costUSDC The USDC cost of the edit.
  /// @param userMint The MT tokens minted to the user.
  /// @param devMint The MT tokens minted to the dev.
  /// @param version The new prompt version, incremented on each edit.
  event PromptEdited(
    address indexed editor,
    uint256 start,
    uint256 end,
    uint256 replacementLen,
    uint256 changed,
    uint256 costUSDC,
    uint256 userMint,
    uint256 devMint,
    uint256 version
  );

  /// @notice Initializes the PolicyManager contract.
  /// @param _usdc The USDC token address.
  /// @param _mtToken The MT token address.
  /// @param _dev The dev share receiver address.
  /// @param _initialPrompt The initial investment policy text.
  constructor(
    address _usdc,
    address _mtToken,
    address _dev,
    address _vault,
    string memory _initialPrompt
  ) {
    if (_usdc == address(0)) revert PolicyManager__InvalidEditRange();
    if (_mtToken == address(0)) revert PolicyManager__InvalidEditRange();
    if (_dev == address(0)) revert PolicyManager__InvalidEditRange();
    VAULT = _vault;
    USDC = _usdc;
    MT_TOKEN = _mtToken;
    DEV = _dev;
    prompt = _initialPrompt;
    promptVersion = 1;
    // @note setting admin
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /// @notice Edits the prompt by replacing a range of characters.
  /// @param start The start index of the edit (inclusive).
  /// @param end The end index of the edit (exclusive).
  /// @param replacement The replacement text.
  /// @dev Validates edit range, calculates cost, transfers USDC, mints MT tokens, and applies the
  /// edit.
  function editPrompt(uint256 start, uint256 end, string calldata replacement)
    external
    nonReentrant
  {
    // Validate edit range
    if (start > end || end > bytes(prompt).length) revert PolicyManager__InvalidEditRange();

    // Validate replacement length matches the range
    if (bytes(replacement).length != end - start) revert PolicyManager__InvalidReplacementLength();

    // Calculate cost units (round up)
    // @note these right?
    uint256 replacementLen = bytes(replacement).length;
    uint256 changed = (replacementLen + 9) / 10;

    // Calculate costs
    uint256 costUSDC = changed * EDIT_PRICE_PER_10_CHARS_USDC;
    uint256 userMint = changed * MT_PER_10CHARS_USER;
    uint256 devMint = (userMint * DEV_BPS) / 10_000;

    // Transfer USDC from user
    IERC20(USDC).transferFrom(msg.sender, VAULT, costUSDC);

    // Mint MT tokens to user and dev
    _mintMT(msg.sender, userMint);
    _mintMT(DEV, devMint);

    // Apply the edit
    _applyEdit(start, end, replacement);

    // Increment version
    promptVersion++;

    // Emit event
    emit PromptEdited(
      msg.sender, start, end, replacementLen, changed, costUSDC, userMint, devMint, promptVersion
    );
  }

  /// @notice Returns the current prompt and version.
  /// @return The current prompt text.
  /// @return The current prompt version.
  function getPrompt() external view returns (string memory, uint256) {
    return (prompt, promptVersion);
  }

  // @note sure about this one. Might be from scope lift. Could be useful.
  /// @notice Returns a slice of the prompt for gas efficiency.
  /// @param start The start index (inclusive).
  /// @param end The end index (exclusive).
  /// @return The substring of the prompt.
  function getPromptSlice(uint256 start, uint256 end) external view returns (string memory) {
    if (start > end || end > bytes(prompt).length) revert PolicyManager__InvalidEditRange();

    bytes memory promptBytes = bytes(prompt);
    bytes memory slice = new bytes(end - start);

    for (uint256 i = start; i < end; i++) {
      slice[i - start] = promptBytes[i];
    }

    return string(slice);
  }

  /// @notice Calculates the cost of an edit without executing it.
  /// @param changed The number of 10-character units that would be changed.
  /// @return costUSDC The USDC cost of the edit.
  /// @return userMint The MT tokens that would be minted to the user.
  /// @return devMint The MT tokens that would be minted to the dev.
  function previewEditCost(uint256 changed)
    external
    pure
    returns (uint256 costUSDC, uint256 userMint, uint256 devMint)
  {
    costUSDC = changed * EDIT_PRICE_PER_10_CHARS_USDC;
    userMint = changed * MT_PER_10CHARS_USER;
    devMint = (userMint * DEV_BPS) / 10_000;
  }

  /// @notice Internal function to mint MT tokens.
  /// @param to The address to mint tokens to.
  /// @param amount The amount of tokens to mint.
  function _mintMT(address to, uint256 amount) internal {
    ManagementToken(MT_TOKEN).mint(to, amount);
  }

  // taken from https://github.com/Vectorized/solady/blob/main/src/utils/LibBytes.sol
  /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
  /// `start` and `end` are byte offsets.
  function slice(bytes memory subject, uint256 start, uint256 end)
    internal
    pure
    returns (bytes memory result)
  {
    /// @solidity memory-safe-assembly
    assembly {
      let l := mload(subject) // Subject length.
      if iszero(gt(l, end)) { end := l }
      if iszero(gt(l, start)) { start := l }
      if lt(start, end) {
        result := mload(0x40)
        let n := sub(end, start)
        let i := add(subject, start)
        let w := not(0x1f)
        // Copy the `subject` one word at a time, backwards.
        for { let j := and(add(n, 0x1f), w) } 1 {} {
          mstore(add(result, j), mload(add(i, j)))
          j := add(j, w) // `sub(j, 0x20)`.
          if iszero(j) { break }
        }
        let o := add(add(result, 0x20), n)
        mstore(o, 0) // Zeroize the slot after the bytes.
        mstore(0x40, add(o, 0x20)) // Allocate memory.
        mstore(result, n) // Store the length.
      }
    }
  }

  // taken from https://github.com/Vectorized/solady/blob/main/src/utils/LibBytes.sol
  /// @dev Returns a concatenated bytes of `a` and `b`.
  /// Cheaper than `bytes.concat()` and does not de-align the free memory pointer.
  function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory result) {
    /// @solidity memory-safe-assembly
    assembly {
      result := mload(0x40)
      let w := not(0x1f)
      let aLen := mload(a)
      // Copy `a` one word at a time, backwards.
      for { let o := and(add(aLen, 0x20), w) } 1 {} {
        mstore(add(result, o), mload(add(a, o)))
        o := add(o, w) // `sub(o, 0x20)`.
        if iszero(o) { break }
      }
      let bLen := mload(b)
      let output := add(result, aLen)
      // Copy `b` one word at a time, backwards.
      for { let o := and(add(bLen, 0x20), w) } 1 {} {
        mstore(add(output, o), mload(add(b, o)))
        o := add(o, w) // `sub(o, 0x20)`.
        if iszero(o) { break }
      }
      let totalLen := add(aLen, bLen)
      let last := add(add(result, 0x20), totalLen)
      mstore(last, 0) // Zeroize the slot after the bytes.
      mstore(result, totalLen) // Store the length.
      mstore(0x40, add(last, 0x20)) // Allocate memory.
    }
  }

  /// @notice Internal function to apply the edit to the prompt.
  /// @param start The start index of the edit.
  /// @param end The end index of the edit.
  /// @param replacement The replacement text.
  function _applyEdit(uint256 start, uint256 end, string calldata replacement)
    internal
    returns (string memory)
  {
    bytes memory promptBytes = bytes(prompt);

    // Copy the part before the edit
    bytes memory p1 = slice(bytes(prompt), 0, start);
    // Copy the part after the edit
    bytes memory p2 = slice(bytes(prompt), end, promptBytes.length);
    // Concatenate the edit to the fist part
    bytes memory temp = concat(p1, bytes(replacement));
    // string(concat(concat(slice(bytes(prompt), 0, start), bytes(replacement)), p2));

    prompt = string(concat(temp, p2));
  }
}
