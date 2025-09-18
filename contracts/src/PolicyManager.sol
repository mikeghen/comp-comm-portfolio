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
  constructor(address _usdc, address _mtToken, address _dev, string memory _initialPrompt) {
    if (_usdc == address(0)) revert PolicyManager__InvalidEditRange();
    if (_mtToken == address(0)) revert PolicyManager__InvalidEditRange();
    if (_dev == address(0)) revert PolicyManager__InvalidEditRange();

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
    IERC20(USDC).transferFrom(msg.sender, address(this), costUSDC);

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

  /// @notice Internal function to apply the edit to the prompt.
  /// @param start The start index of the edit.
  /// @param end The end index of the edit.
  /// @param replacement The replacement text.
  function _applyEdit(uint256 start, uint256 end, string calldata replacement) internal {
    bytes memory promptBytes = bytes(prompt);
    bytes memory replacementBytes = bytes(replacement);

    // Create new bytes array for the result
    bytes memory newPrompt = new bytes(promptBytes.length - (end - start) + replacementBytes.length);

    // Copy the part before the edit
    for (uint256 i = 0; i < start; i++) {
      newPrompt[i] = promptBytes[i];
    }

    // Copy the replacement
    for (uint256 i = 0; i < replacementBytes.length; i++) {
      newPrompt[start + i] = replacementBytes[i];
    }

    // Copy the part after the edit
    for (uint256 i = end; i < promptBytes.length; i++) {
      newPrompt[start + replacementBytes.length + (i - end)] = promptBytes[i];
    }

    prompt = string(newPrompt);
  }
}
