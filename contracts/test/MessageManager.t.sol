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
  address vault;
  // Role constants
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 constant AGENT_ROLE = keccak256("AGENT_ROLE");

  function setUp() public virtual {
    admin = makeAddr("Admin");
    agent = makeAddr("Agent");
    dev = makeAddr("Dev");
    payer = makeAddr("Payer");
    relayer = makeAddr("Relayer");
    vault = makeAddr("Vault");

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
    messageManager = new MessageManager(address(usdc), address(mtToken), dev, agent, admin, vault);
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

  function _computeMessageHash(string memory message) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(message));
  }
}

contract Constructor is MessageManagerTest {
  function test_SetsConfigurationParameters() public view {
    assertEq(messageManager.USDC(), address(usdc));
    assertEq(messageManager.MT_TOKEN(), address(mtToken));
    assertEq(messageManager.DEV(), dev);
  }

  function test_GrantsRoles() public view {
    assertTrue(messageManager.hasRole(AGENT_ROLE, agent));
    assertTrue(messageManager.hasRole(messageManager.DEFAULT_ADMIN_ROLE(), admin));
  }

  function test_RevertIf_UsdcZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(0), address(mtToken), dev, agent, admin, vault);
  }

  function test_RevertIf_MtTokenZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(0), dev, agent, admin, vault);
  }

  function test_RevertIf_DevZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), address(0), agent, admin, vault);
  }

  function test_RevertIf_AgentZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), dev, address(0), admin, vault);
  }

  function test_RevertIf_AdminZeroAddress() public {
    vm.expectRevert(MessageManager.MessageManager__InvalidAddress.selector);
    new MessageManager(address(usdc), address(mtToken), dev, agent, address(0), vault);
  }
}

contract PayForMessage is MessageManagerTest {
  function test_PaysForMessage() public {
    // ---- Arrange
    string memory message = "hello world";
    bytes32 messageHash = _computeMessageHash(message);

    // Fund and approve payer
    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price);
    _approveUsdcFrom(payer, type(uint256).max);

    uint256 userMint = messageManager.MT_PER_MESSAGE_USER();
    uint256 devMint = (userMint * messageManager.DEV_BPS()) / 10_000;

    // Expect event
    vm.expectEmit(true, true, true, true);
    emit MessageManager.MessagePaid(messageHash, payer, userMint, devMint);

    // ---- Act
    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Assert
    assertEq(messageManager.paidMessages(messageHash), message);
    assertEq(usdc.balanceOf(address(vault)), price);
    assertEq(mtToken.balanceOf(payer), userMint);
    assertEq(mtToken.balanceOf(dev), devMint);
  }

  function test_AllowsRepaymentOfSameMessage() public {
    // ---- Arrange
    string memory message = "duplicate message";
    bytes32 messageHash = _computeMessageHash(message);
    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price * 2);
    _approveUsdcFrom(payer, type(uint256).max);

    uint256 userMint = messageManager.MT_PER_MESSAGE_USER();
    uint256 devMint = (userMint * messageManager.DEV_BPS()) / 10_000;

    // Pay for message first time
    vm.prank(payer);
    messageManager.payForMessage(message);

    // Process the message
    vm.prank(agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Act - second payment should succeed after processing
    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Assert
    // Both payments should be recorded
    assertEq(usdc.balanceOf(address(vault)), price * 2);
    // Tokens minted twice (2x user mint + 2x dev mint)
    assertEq(mtToken.balanceOf(payer), userMint * 2);
    assertEq(mtToken.balanceOf(dev), devMint * 2);
  }

  function test_RevertIf_PayingForPendingMessage() public {
    // ---- Arrange
    string memory message = "pending message";
    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price * 2);
    _approveUsdcFrom(payer, type(uint256).max);

    // Pay for message first time
    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Act & Assert - second payment should revert (message pending processing)
    vm.expectRevert(MessageManager.MessageManager__PendingProcessing.selector);
    vm.prank(payer);
    messageManager.payForMessage(message);
  }

  function test_AllowsDifferentMessagesFromSamePayer() public {
    // ---- Arrange
    string memory message1 = "first message";
    string memory message2 = "second message";
    bytes32 messageHash1 = _computeMessageHash(message1);
    bytes32 messageHash2 = _computeMessageHash(message2);

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price * 2);
    _approveUsdcFrom(payer, type(uint256).max);

    // ---- Act - pay for both messages
    vm.prank(payer);
    messageManager.payForMessage(message1);

    vm.prank(payer);
    messageManager.payForMessage(message2);

    // ---- Assert - both messages should be stored
    assertEq(messageManager.paidMessages(messageHash1), message1);
    assertEq(messageManager.paidMessages(messageHash2), message2);
    assertEq(usdc.balanceOf(address(vault)), price * 2);
  }

  function test_RevertIf_MessagePendingProcessing() public {
    // ---- Arrange
    string memory message = "shared message";
    bytes32 messageHash = _computeMessageHash(message);
    address payer2 = makeAddr("Payer2");

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price);
    _mintUsdcTo(payer2, price);
    _approveUsdcFrom(payer, type(uint256).max);
    _approveUsdcFrom(payer2, type(uint256).max);

    // ---- Act - first payer pays
    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Assert - second payer should revert (message pending processing)
    vm.expectRevert(MessageManager.MessageManager__PendingProcessing.selector);
    vm.prank(payer2);
    messageManager.payForMessage(message);

    // Only first payer's payment should be recorded
    assertEq(messageManager.paidMessages(messageHash), message);
    assertEq(usdc.balanceOf(address(vault)), price); // Only one payment
  }

  function test_AllowsSameMessageFromDifferentPayersAfterProcessing() public {
    // ---- Arrange
    string memory message = "shared message";
    bytes32 messageHash = _computeMessageHash(message);
    address payer2 = makeAddr("Payer2");

    uint256 price = messageManager.MESSAGE_PRICE_USDC();
    _mintUsdcTo(payer, price);
    _mintUsdcTo(payer2, price);
    _approveUsdcFrom(payer, type(uint256).max);
    _approveUsdcFrom(payer2, type(uint256).max);

    uint256 userMint = messageManager.MT_PER_MESSAGE_USER();
    uint256 devMint = (userMint * messageManager.DEV_BPS()) / 10_000;

    // ---- Act - first payer pays
    vm.prank(payer);
    messageManager.payForMessage(message);

    // Process the message
    vm.prank(agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Act - second payer can now pay after message is processed
    vm.prank(payer2);
    messageManager.payForMessage(message);

    // ---- Assert - both payments should be recorded
    assertEq(messageManager.paidMessages(messageHash), message);
    assertEq(usdc.balanceOf(address(vault)), price * 2); // Both payments
    assertEq(mtToken.balanceOf(payer), userMint); // First payer gets tokens
    assertEq(mtToken.balanceOf(payer2), userMint); // Second payer gets tokens
    assertEq(mtToken.balanceOf(dev), devMint * 2); // Dev gets tokens from both
  }

  function test_RevertIf_InsufficientUsdcBalance() public {
    // ---- Arrange
    string memory message = "expensive message";
    uint256 price = messageManager.MESSAGE_PRICE_USDC();

    // Give payer less than required
    _mintUsdcTo(payer, price - 1);
    _approveUsdcFrom(payer, type(uint256).max);

    // ---- Act & Assert
    vm.expectRevert(); // ERC20 transfer will revert
    vm.prank(payer);
    messageManager.payForMessage(message);
  }

  function test_RevertIf_InsufficientUsdcApproval() public {
    // ---- Arrange
    string memory message = "unapproved message";
    uint256 price = messageManager.MESSAGE_PRICE_USDC();

    _mintUsdcTo(payer, price);
    // Don't approve or approve insufficient amount
    vm.prank(payer);
    usdc.approve(address(messageManager), price - 1);

    // ---- Act & Assert
    vm.expectRevert(); // ERC20 transferFrom will revert
    vm.prank(payer);
    messageManager.payForMessage(message);
  }
}

contract MarkMessageProcessed is MessageManagerTest {
  function test_MarksProcessedWhenPaid() public {
    // ---- Arrange
    string memory message = "process me";
    bytes32 messageHash = _computeMessageHash(message);

    // Fund and approve
    _mintUsdcTo(payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(payer, type(uint256).max);

    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Act
    vm.prank(agent);
    vm.expectEmit(true, true, true, true);
    emit MessageManager.MessageProcessed(messageHash, agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Assert
    assertTrue(messageManager.processedMessages(messageHash));
  }

  function test_RevertIf_CalledByNonAgent(address _caller) public {
    vm.assume(_caller != agent);
    string memory message = "fake message";
    bytes32 messageHash = _computeMessageHash(message);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, AGENT_ROLE
      )
    );
    vm.prank(_caller);
    messageManager.markMessageProcessed(messageHash);
  }

  function test_RevertIf_NotPaid() public {
    string memory message = "unpaid message";
    bytes32 messageHash = _computeMessageHash(message);
    vm.prank(agent);
    vm.expectRevert(MessageManager.MessageManager__NotPaid.selector);
    messageManager.markMessageProcessed(messageHash);
  }

  function test_RevertIf_AlreadyProcessed() public {
    // ---- Arrange
    string memory message = "double process";
    bytes32 messageHash = _computeMessageHash(message);

    _mintUsdcTo(payer, messageManager.MESSAGE_PRICE_USDC());
    _approveUsdcFrom(payer, type(uint256).max);

    vm.prank(payer);
    messageManager.payForMessage(message);

    vm.prank(agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Assert
    vm.prank(agent);
    vm.expectRevert(MessageManager.MessageManager__AlreadyProcessed.selector);
    messageManager.markMessageProcessed(messageHash);
  }

  function test_AllowsResendingAfterRepayment() public {
    // ---- Arrange
    string memory message = "resend me";
    bytes32 messageHash = _computeMessageHash(message);
    uint256 price = messageManager.MESSAGE_PRICE_USDC();

    // Fund payer for two payments
    _mintUsdcTo(payer, price * 2);
    _approveUsdcFrom(payer, type(uint256).max);

    // ---- Act - First send cycle
    vm.prank(payer);
    messageManager.payForMessage(message);

    vm.prank(agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Assert - message is processed
    assertTrue(messageManager.processedMessages(messageHash));

    // ---- Act - Pay for the same message again
    vm.prank(payer);
    messageManager.payForMessage(message);

    // ---- Assert - processed flag should be reset
    assertFalse(messageManager.processedMessages(messageHash));

    // ---- Act - Process the message again
    vm.prank(agent);
    messageManager.markMessageProcessed(messageHash);

    // ---- Assert - message is processed again
    assertTrue(messageManager.processedMessages(messageHash));
  }
}

contract Constants is MessageManagerTest {
  function test_MessagePrice() public view {
    // TODO: Change back to 10_000_000 (10 USDC) before mainnet deploy, lowered for testnet
    assertEq(messageManager.MESSAGE_PRICE_USDC(), 1_000_000);
  }

  function test_MtPerMessageUser() public view {
    assertEq(messageManager.MT_PER_MESSAGE_USER(), 1_000_000_000_000_000_000);
  }

  function test_DevBps() public view {
    assertEq(messageManager.DEV_BPS(), 2000);
  }
}
