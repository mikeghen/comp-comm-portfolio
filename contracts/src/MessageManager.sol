// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ManagementToken} from "./ManagementToken.sol";

/// @title MessageManager
/// @notice Handles USDC payments for AI agent messages and MT minting with replay protection.
///@dev Uses AccessControl for agent permissions and EIP-712 for auth .
contract MessageManager is AccessControl, ReentrancyGuard, EIP712 {
    /// @notice Thrown when a message has already been paid.
    error MessageManager__AlreadyPaid();

    /// @notice Thrown when a message has already been processed.
    error MessageManager__AlreadyProcessed();

    /// @notice Thrown when attempting to process an unpaid message.
    error MessageManager__NotPaid();

    /// @notice Thrown when an invalid constructor address is provided.
    error MessageManager__InvalidAddress();

    /// @notice Thrown when the provided signature is invalid for the payer and message.
    error MessageManager__InvalidSignature();

    /// @notice Role for agent that can mark messages as processed.
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    /// @notice Message typed data for EIP-712 signing.
    struct Message {
        bytes32 messageHash;
        address payer;
        uint256 nonce;
    }

    /// @notice Mapping of EIP-712 message digest to payment status.
    mapping(bytes32 digest => bool paid) public paidMessages;

    /// @notice Mapping of EIP-712 message digest to processed status.
    mapping(bytes32 digest => bool processed) public processedMessages;

    /// @notice USDC token address.
    address public immutable USDC;

    /// @notice MT token address.
    address public immutable MT_TOKEN;

    /// @notice Vault Address
    address public immutable VAULT;
    
    /// @notice Dev share receiver.
    address public immutable DEV;

    /// @notice Message price: 10 USDC (6 decimals).
    uint256 public constant MESSAGE_PRICE_USDC = 10_000_000;

    /// @notice MT minted per message to user: 1.0 MT (18 decimals).
    uint256 public constant MT_PER_MESSAGE_USER = 1_000_000_000_000_000_000;

    /// @notice Dev share in basis points: 20%.
    uint256 public constant DEV_BPS = 2000;

    /// @notice EIP-712 typehash for Message struct.
    bytes32 public constant MESSAGE_TYPEHASH =
        keccak256("Message(bytes32 messageHash,address payer,uint256 nonce)");

    /// @notice Emitted when a message is paid.
    /// @param sigHash The EIP-712 digest for the message (named for backwards compatibility).
    /// @param payer The address paying for the message.
    /// @param messageURI A human-readable URI/pointer to the message content.
    /// @param messageHash The keccak256 hash of the off-chain message content.
    /// @param userMint Amount of MT minted to the payer.
    /// @param devMint Amount of MT minted to the dev address.
    event MessagePaid(
        bytes32 indexed sigHash,
        address indexed payer,
        string messageURI,
        bytes32 messageHash,
        uint256 userMint,
        uint256 devMint
    );

    /// @notice Emitted when a message is processed by the agent.
    /// @param sigHash The EIP-712 digest for the previously paid message (name preserved).
    /// @param processor The address that processed the message (must have AGENT_ROLE).
    event MessageProcessed(bytes32 indexed sigHash, address indexed processor);

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
    ) EIP712("MessageManager", "1") {
        if (
            _usdc == address(0) ||
            _mtToken == address(0) ||
            _dev == address(0) ||
            _agent == address(0) ||
            _admin == address(0)||
            _vault == address(0)
        ) revert MessageManager__InvalidAddress();

        USDC = _usdc;
        MT_TOKEN = _mtToken;
        DEV = _dev;
        VAULT = _vault;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(AGENT_ROLE, _agent);
    }

    /// @notice Pays for a message using an EIP-712 signature and mints MT to user and dev.
    /// @param m The message payload including content hash, payer, and nonce.
    /// @param sig The EIP-712/EIP-1271 signature authorizing this message payment.
    /// @param messageURI A human-readable URI/pointer to the message content for off-chain indexing.
    function payForMessageWithSig(
        Message calldata m,
        bytes calldata sig,
        string calldata messageURI
    ) external nonReentrant {
        // Compute EIP-712 digest
        bytes32 structHash = keccak256(
            abi.encode(MESSAGE_TYPEHASH, m.messageHash, m.payer, m.nonce)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // Use digest as replay key (robust to signature malleability variations like EIP-2098)
        if (paidMessages[digest]) revert MessageManager__AlreadyPaid();

        // Validate signature from payer (EOA or ERC1271)
        bool isValid = SignatureChecker.isValidSignatureNow(
            m.payer,
            digest,
            sig
        );
        if (!isValid) revert MessageManager__InvalidSignature();

        // Mark paid before external calls (reentrancy safety)
        paidMessages[digest] = true;

        // Transfer fixed USDC price from payer to this contract
        IERC20(USDC).transferFrom(m.payer, VAULT, MESSAGE_PRICE_USDC);

        // Compute mint amounts
        uint256 userMint = MT_PER_MESSAGE_USER;
        uint256 devMint = (userMint * DEV_BPS) / 10_000;

        // Mint tokens
        ManagementToken(MT_TOKEN).mint(m.payer, userMint);
        ManagementToken(MT_TOKEN).mint(DEV, devMint);

        emit MessagePaid(
            digest,
            m.payer,
            messageURI,
            m.messageHash,
            userMint,
            devMint
        );
    }

    /// @notice Marks a previously paid message as processed. Only callable by agent role.
    /// @param sigHash The EIP-712 digest used when paying for the message (name preserved).
    function markMessageProcessed(
        bytes32 sigHash
    ) external onlyRole(AGENT_ROLE) {
        if (!paidMessages[sigHash]) revert MessageManager__NotPaid();
        if (processedMessages[sigHash])
            revert MessageManager__AlreadyProcessed();

        processedMessages[sigHash] = true;
        emit MessageProcessed(sigHash, msg.sender);
    }

    /// @notice Returns the EIP-712 domain separator (exposed for testing).
    function exposed_DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
