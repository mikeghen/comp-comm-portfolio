// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ManagementToken} from "./ManagementToken.sol";

/// @title MessageManager
/// @notice Handles USDC payments for AI agent messages and MT minting with replay protection.
/// @dev Uses AccessControl for agent permissions.
contract MessageManager is AccessControl, ReentrancyGuard {
  /// @notice Thrown when a message has already been processed.
  error MessageManager__AlreadyProcessed();

  /// @notice Thrown when attempting to process an unpaid message.
  error MessageManager__NotPaid();

  /// @notice Thrown when an invalid constructor address is provided.
  error MessageManager__InvalidAddress();

  /// @notice Role for agent that can mark messages as processed.
  bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

  /// @notice Mapping of message hash to message content and payment status.
  mapping(bytes32 messageHash => string message) public paidMessages;

  /// @notice Mapping of message hash to processed status.
  mapping(bytes32 messageHash => bool processed) public processedMessages;

  /// @notice USDC token address.
  address public immutable USDC;

  /// @notice MT token address.
  address public immutable MT_TOKEN;

  /// @notice Vault Address
  address public immutable VAULT;

  /// @notice Dev share receiver.
  address public immutable DEV;

  /// @notice Message price: 10 USDC (6 decimals).
  /// TODO: Change back to 10 USDC for mainnet deployment.
  uint256 public constant MESSAGE_PRICE_USDC = 1_000_000;

  /// @notice MT minted per message to user: 1.0 MT (18 decimals).
  uint256 public constant MT_PER_MESSAGE_USER = 1_000_000_000_000_000_000;

  /// @notice Dev share in basis points: 20%.
  uint256 public constant DEV_BPS = 2000;

  /// @notice Emitted when a message is paid.
  /// @param messageHash The keccak256 hash of the message content.
  /// @param payer The address paying for the message.
  /// @param userMint Amount of MT minted to the payer.
  /// @param devMint Amount of MT minted to the dev address.
  event MessagePaid(
    bytes32 indexed messageHash, address indexed payer, uint256 userMint, uint256 devMint
  );

  /// @notice Emitted when a message is processed by the agent.
  /// @param messageHash The keccak256 hash of the processed message.
  /// @param processor The address that processed the message (must have AGENT_ROLE).
  event MessageProcessed(bytes32 indexed messageHash, address indexed processor);

  /// @notice Initializes the MessageManager.
  /// @param _usdc USDC token address.
  /// @param _mtToken MT token address.
  /// @param _dev Dev share receiver address.
  /// @param _agent Agent address to be granted AGENT_ROLE.
  /// @param _admin Admin address for AccessControl DEFAULT_ADMIN_ROLE.
  constructor(
    address _usdc,
    address _mtToken,
    address _dev,
    address _agent,
    address _admin,
    address _vault
  ) {
    if (
      _usdc == address(0) || _mtToken == address(0) || _dev == address(0) || _agent == address(0)
        || _admin == address(0) || _vault == address(0)
    ) revert MessageManager__InvalidAddress();

    USDC = _usdc;
    MT_TOKEN = _mtToken;
    DEV = _dev;
    VAULT = _vault;
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(AGENT_ROLE, _agent);
  }

  /// @notice Pays for a message and mints MT to user and dev.
  /// @param message The message content to pay for.
  function payForMessage(string calldata message) external nonReentrant {
    // Compute message hash
    bytes32 messageHash = keccak256(abi.encodePacked(message));

    // Store message content with hash as key
    paidMessages[messageHash] = message;

    // Reset processed status to allow resending
    processedMessages[messageHash] = false;

    // Transfer fixed USDC price from payer to vault
    IERC20(USDC).transferFrom(msg.sender, VAULT, MESSAGE_PRICE_USDC);

    // Compute mint amounts
    uint256 userMint = MT_PER_MESSAGE_USER;
    uint256 devMint = (userMint * DEV_BPS) / 10_000;

    // Mint tokens
    ManagementToken(MT_TOKEN).mint(msg.sender, userMint);
    ManagementToken(MT_TOKEN).mint(DEV, devMint);

    emit MessagePaid(messageHash, msg.sender, userMint, devMint);
  }

  /// @notice Marks a previously paid message as processed. Only callable by agent role.
  /// @param messageHash The keccak256 hash of the message to mark as processed.
  function markMessageProcessed(bytes32 messageHash) external onlyRole(AGENT_ROLE) {
    if (bytes(paidMessages[messageHash]).length == 0) revert MessageManager__NotPaid();
    if (processedMessages[messageHash]) revert MessageManager__AlreadyProcessed();

    processedMessages[messageHash] = true;
    emit MessageProcessed(messageHash, msg.sender);
  }
}
