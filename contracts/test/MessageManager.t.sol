// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {MessageManager} from "src/MessageManager.sol";
import {ManagementToken} from "src/ManagementToken.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

contract MessageManagerTest is Test {
  MessageManager messageManager;
  ManagementToken mtToken;
  MockERC20 usdc;

  address admin;
  address agent;
  address dev;
  address payer;
  address relayer;

  // Role constants
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 constant AGENT_ROLE = keccak256("AGENT_ROLE");

  function setUp() public virtual {
    admin = makeAddr("Admin");
    agent = makeAddr("Agent");
    dev = makeAddr("Dev");
    payer = makeAddr("Payer");
    relayer = makeAddr("Relayer");

    vm.label(admin, "Admin");
    vm.label(agent, "Agent");
    vm.label(dev, "Dev");
    vm.label(payer, "Payer");
    vm.label(relayer, "Relayer");

    // Deploy dependencies
    usdc = new MockERC20("USD Coin", "USDC", 6);
    vm.label(address(usdc), "USDC");

    vm.prank(admin);
    mtToken = new ManagementToken(admin);
    vm.label(address(mtToken), "MT Token");

    // Deploy SUT
    messageManager = new MessageManager(address(usdc), address(mtToken), dev, agent, admin);
    vm.label(address(messageManager), "MessageManager");

    // Grant mint role to SUT
    vm.prank(admin);
    mtToken.grantRole(MINTER_ROLE, address(messageManager));
  }

  function _mintUsdcTo(address to, uint256 amount) internal {
    usdc.mint(to, amount);
  }

  function _approveUsdcFrom(address owner, uint256 amount) internal {
    vm.prank(owner);
    usdc.approve(address(messageManager), amount);
  }

  function _computeStructHash(bytes32 _messageHash, address _payer, uint256 _nonce)
    internal
    view
    returns (bytes32)
  {
    return keccak256(abi.encode(messageManager.MESSAGE_TYPEHASH(), _messageHash, _payer, _nonce));
  }

  function _computeDigest(bytes32 structHash) internal view returns (bytes32) {
    bytes32 domainSeparator = messageManager.exposed_DOMAIN_SEPARATOR();
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
  }

  function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  // Build the EIP-712 struct, sign it with payer's key, and return the tuple
  function _buildAndSign(uint256 payerPk, bytes32 contentHash, uint256 nonce)
    internal
    view
    returns (MessageManager.Message memory m, bytes memory sig, bytes32 digest)
  {
    address _payer = vm.addr(payerPk);
    m = MessageManager.Message({messageHash: contentHash, payer: _payer, nonce: nonce});
    bytes32 structHash = _computeStructHash(m.messageHash, m.payer, m.nonce);
    digest = _computeDigest(structHash);
    sig = _signDigest(payerPk, digest);
  }
}

contract Constructor is MessageManagerTest {
  function test_SetsConfigurationParameters() public view {
    assertEq(messageManager.USDC(), address(usdc));
    assertEq(messageManager.MT_TOKEN(), address(mtToken));
    assertEq(messageManager.DEV(), dev);
    assertEq(messageManager.AGENT(), agent);
  }

  function test_GrantsRoles() public view {
    assertTrue(messageManager.hasRole(AGENT_ROLE, agent));
    assertTrue(messageManager.hasRole(messageManager.DEFAULT_ADMIN_ROLE(), admin));
  }

  function test_RevertIf_UsdcZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(0), address(mtToken), dev, agent, admin);
  }

  function test_RevertIf_MtTokenZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(0), dev, agent, admin);
  }

  function test_RevertIf_DevZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), address(0), agent, admin);
  }

  function test_RevertIf_AgentZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), dev, address(0), admin);
  }

  function test_RevertIf_AdminZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), dev, agent, address(0));
  }
}

contract PayForMessageWithSig is MessageManagerTest {
  function test_PaysWithValidSignature_FromPayerDirectly() public {
    // ---- Arrange
    uint256 payerPk = 0xA11CE;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("hello world");
    (MessageManager.Message memory m, bytes memory sig, bytes32 digest) =
      _buildAndSign(payerPk, contentHash, 1);

    // Fund and approve payer
    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(_payer, price);
    _approveUsdcFrom(_payer, type(uint256).max);

    uint256 userMint = messageManager.MT_PER_MESSAGE_USER();
    uint256 devMint = (userMint * messageManager.DEV_BPS()) / 10_000;

    // Expect event
    vm.expectEmit(true, true, true, true);
    emit MessageManager.MessagePaid(digest, _payer, "ipfs://msg", contentHash, userMint, devMint);

    // ---- Act
    vm.prank(_payer);
    messageManager.payForMessageWithSig(m, sig, "ipfs://msg");

    // ---- Assert
    assertTrue(messageManager.paidMessages(digest));
    assertEq(usdc.balanceOf(address(messageManager)), price);
    assertEq(mtToken.balanceOf(_payer), userMint);
    assertEq(mtToken.balanceOf(dev), devMint);
  }

  function test_PaysWithValidSignature_ViaRelayer() public {
    // ---- Arrange
    uint256 payerPk = 0xB0B;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("relayed message");
    (MessageManager.Message memory m, bytes memory sig, bytes32 digest) =
      _buildAndSign(payerPk, contentHash, 5);

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(_payer, price);
    _approveUsdcFrom(_payer, type(uint256).max);

    // ---- Act (relayer submits)
    vm.prank(relayer);
    messageManager.payForMessageWithSig(m, sig, "ar://relayed");

    // ---- Assert
    assertTrue(messageManager.paidMessages(digest));
    assertEq(usdc.balanceOf(address(messageManager)), price);
  }

  function test_RevertIf_InvalidSignature() public {
    // ---- Arrange
    uint256 payerPk = 0xC0FFEE;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("bad sig");
    (MessageManager.Message memory m,, bytes32 digest) = _buildAndSign(payerPk, contentHash, 7);

    // Sign with wrong key
    uint256 wrongPk = 0xBAD;
    bytes memory invalidSig = _signDigest(wrongPk, digest);

    _mintUsdcTo(_payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(_payer, type(uint256).max);

    vm.expectRevert(MessageManager.MessageManager__InvalidSignature.selector);
    messageManager.payForMessageWithSig(m, invalidSig, "uri");
  }

  function test_RevertIf_ReplayedSameDigestWithDifferentSignatureEncodings() public {
    // ---- Arrange
    uint256 payerPk = 0xD00D;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("replay");
    (MessageManager.Message memory m, bytes memory sig65, bytes32 digest) =
      _buildAndSign(payerPk, contentHash, 123);

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(_payer, price * 2);
    _approveUsdcFrom(_payer, type(uint256).max);

    // First call succeeds with 65-byte signature
    messageManager.payForMessageWithSig(m, sig65, "uri");

    // Build compact 64-byte (EIP-2098) signature for the same digest
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);
    bytes32 vs = bytes32(uint256(s) | (uint256(v - 27) << 255));
    bytes memory sig64 = abi.encodePacked(r, vs);

    // Second call should revert due to same digest already paid
    vm.expectRevert(MessageManager.MessageManager__AlreadyPaid.selector);
    messageManager.payForMessageWithSig(m, sig64, "uri");

    // Ensure mapping set on digest
    assertTrue(messageManager.paidMessages(digest));
  }

  function test_RevertIf_TamperedMessageAfterSigning() public {
    // ---- Arrange
    uint256 payerPk = 0xDEADBEEF;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("original");
    (MessageManager.Message memory m, bytes memory sig,) = _buildAndSign(payerPk, contentHash, 1);

    // Tamper the struct: change nonce
    m.nonce = 2;

    _mintUsdcTo(_payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(_payer, type(uint256).max);

    // ---- Assert revert due to invalid signature for tampered struct
    vm.expectRevert(MessageManager.MessageManager__InvalidSignature.selector);
    messageManager.payForMessageWithSig(m, sig, "uri");
  }

  function test_AllowsNewSignatureWithDifferentNonce() public {
    // ---- Arrange
    uint256 payerPk = 0xACDC;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("same content");
    (MessageManager.Message memory m1, bytes memory sig1, bytes32 digest1) =
      _buildAndSign(payerPk, contentHash, 1);
    (MessageManager.Message memory m2, bytes memory sig2, bytes32 digest2) =
      _buildAndSign(payerPk, contentHash, 2);

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(_payer, price * 2);
    _approveUsdcFrom(_payer, type(uint256).max);

    // ---- Act & Assert: both succeed because digests differ (nonce)
    messageManager.payForMessageWithSig(m1, sig1, "uri1");
    messageManager.payForMessageWithSig(m2, sig2, "uri2");

    assertTrue(messageManager.paidMessages(digest1));
    assertTrue(messageManager.paidMessages(digest2));
  }
}

contract MarkMessageProcessed is MessageManagerTest {
  function test_MarksProcessedWhenPaid() public {
    // ---- Arrange
    uint256 payerPk = 0xAAA;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("process me");

    (MessageManager.Message memory m, bytes memory sig, bytes32 digest) =
      _buildAndSign(payerPk, contentHash, 42);

    // Fund and approve
    _mintUsdcTo(_payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(_payer, type(uint256).max);

    messageManager.payForMessageWithSig(m, sig, "uri");

    // ---- Act
    vm.prank(agent);
    vm.expectEmit(true, true, true, true);
    emit MessageManager.MessageProcessed(digest, agent);
    messageManager.markMessageProcessed(digest);

    // ---- Assert
    assertTrue(messageManager.processedMessages(digest));
  }

  function test_RevertIf_CalledByNonAgent(address _caller) public {
    vm.assume(_caller != agent);
    bytes32 digest = keccak256("fake");

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, AGENT_ROLE
      )
    );
    vm.prank(_caller);
    messageManager.markMessageProcessed(digest);
  }

  function test_RevertIf_NotPaid() public {
    bytes32 digest = keccak256("notpaid");
    vm.prank(agent);
    vm.expectRevert(MessageManager.MessageManager__NotPaid.selector);
    messageManager.markMessageProcessed(digest);
  }

  function test_RevertIf_AlreadyProcessed() public {
    // ---- Arrange
    uint256 payerPk = 0xBBB;
    address _payer = vm.addr(payerPk);
    bytes32 contentHash = keccak256("double process");
    (MessageManager.Message memory m, bytes memory sig, bytes32 digest) =
      _buildAndSign(payerPk, contentHash, 99);

    _mintUsdcTo(_payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(_payer, type(uint256).max);
    messageManager.payForMessageWithSig(m, sig, "uri");

    vm.prank(agent);
    messageManager.markMessageProcessed(digest);

    // ---- Assert
    vm.prank(agent);
    vm.expectRevert(MessageManager.MessageManager__AlreadyProcessed.selector);
    messageManager.markMessageProcessed(digest);
  }
}

contract Constants is MessageManagerTest {
  function test_MessagePrice() public view {
    assertEq(messageManager.MESSAGE_PRICE_USDC(), 10_000_000);
  }

  function test_MtPerMessageUser() public view {
    assertEq(messageManager.MT_PER_MESSAGE_USER(), 1_000_000_000_000_000_000);
  }

  function test_DevBps() public view {
    assertEq(messageManager.DEV_BPS(), 2000);
  }
}
