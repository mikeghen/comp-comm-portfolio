// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyManager} from "src/PolicyManager.sol";
import {ManagementToken} from "src/ManagementToken.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract PolicyManagerTest is Test {
  PolicyManager policyManager;
  ManagementToken mtToken;
  MockERC20 usdc;
  address admin;
  address dev;
  string initialPrompt;

  // Role constants
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

  function setUp() public virtual {
    admin = makeAddr("Admin");
    dev = makeAddr("Dev");
    initialPrompt = "Initial investment policy: Invest in blue chip stocks and bonds.";

    // Deploy mock USDC
    usdc = new MockERC20("USD Coin", "USDC", 6);
    vm.label(address(usdc), "USDC");

    // Deploy MT token
    vm.prank(admin);
    mtToken = new ManagementToken(admin);
    vm.label(address(mtToken), "MT Token");

    // Deploy PolicyManager
    policyManager = new PolicyManager(address(usdc), address(mtToken), dev, initialPrompt);
    vm.label(address(policyManager), "PolicyManager");

    // Grant MINTER_ROLE to PolicyManager so it can mint MT tokens
    vm.prank(admin);
    mtToken.grantRole(MINTER_ROLE, address(policyManager));
  }

  function _assumeSafeAddress(address _address) internal pure {
    vm.assume(_address != address(0));
  }

  function _boundToReasonableLength(uint256 _length) internal pure returns (uint256) {
    return bound(_length, 1, 1000);
  }

  function _boundToReasonableEditRange(uint256 _start, uint256 _end, uint256 _promptLength)
    internal
    pure
    returns (uint256, uint256)
  {
    _start = bound(_start, 0, _promptLength);
    _end = bound(_end, _start, _promptLength);
    return (_start, _end);
  }

  function _boundToReasonableCost(uint256 _cost) internal pure returns (uint256) {
    return bound(_cost, 1, 1000);
  }
}

contract Constructor is PolicyManagerTest {
  function test_SetsConfigurationParameters() public view {
    assertEq(policyManager.USDC(), address(usdc));
    assertEq(policyManager.MT_TOKEN(), address(mtToken));
    assertEq(policyManager.DEV(), dev);
    assertEq(policyManager.prompt(), initialPrompt);
    assertEq(policyManager.promptVersion(), 1);
  }

  function testFuzz_SetsConfigurationParametersToArbitraryValues(
    address _usdc,
    address _mtToken,
    address _dev,
    string memory _initialPrompt
  ) public {
    _assumeSafeAddress(_usdc);
    _assumeSafeAddress(_mtToken);
    _assumeSafeAddress(_dev);

    PolicyManager _policyManager = new PolicyManager(_usdc, _mtToken, _dev, _initialPrompt);

    assertEq(_policyManager.USDC(), _usdc);
    assertEq(_policyManager.MT_TOKEN(), _mtToken);
    assertEq(_policyManager.DEV(), _dev);
    assertEq(_policyManager.prompt(), _initialPrompt);
    assertEq(_policyManager.promptVersion(), 1);
  }

  function testFuzz_RevertIf_UsdcAddressIsZero(
    address _mtToken,
    address _dev,
    string memory _initialPrompt
  ) public {
    _assumeSafeAddress(_mtToken);
    _assumeSafeAddress(_dev);

    vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
    new PolicyManager(address(0), _mtToken, _dev, _initialPrompt);
  }

  function testFuzz_RevertIf_MtTokenAddressIsZero(
    address _usdc,
    address _dev,
    string memory _initialPrompt
  ) public {
    _assumeSafeAddress(_usdc);
    _assumeSafeAddress(_dev);

    vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
    new PolicyManager(_usdc, address(0), _dev, _initialPrompt);
  }

  function testFuzz_RevertIf_DevAddressIsZero(
    address _usdc,
    address _mtToken,
    string memory _initialPrompt
  ) public {
    _assumeSafeAddress(_usdc);
    _assumeSafeAddress(_mtToken);

    vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
    new PolicyManager(_usdc, _mtToken, address(0), _initialPrompt);
  }
}

contract EditPrompt is PolicyManagerTest {
  address user;

  function setUp() public override {
    super.setUp();

    // Set up user for testing
    user = makeAddr("User");
    vm.label(user, "User");
  }

  function _fundUserAndApprove(uint256 amount) internal {
    usdc.mint(user, amount);
    vm.prank(user);
    usdc.approve(address(policyManager), type(uint256).max);
  }

  function testFuzz_EditsPromptWithValidRange(
    uint256 _start,
    uint256 _end,
    string memory _replacement
  ) public {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Create replacement of exact length needed
    uint256 rangeLength = _end - _start;
    bytes memory newReplacement = new bytes(rangeLength);
    for (uint256 i = 0; i < rangeLength; i++) {
      newReplacement[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
    }
    _replacement = string(newReplacement);

    uint256 expectedVersion = policyManager.promptVersion() + 1;
    uint256 expectedChanged = (rangeLength + 9) / 10;
    uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
    uint256 expectedUserMint = expectedChanged * policyManager.MT_PER_10CHARS_USER();
    uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10_000;

    _fundUserAndApprove(expectedCostUSDC + 1e6); // Extra for safety

    // ---- Act
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);

    // ---- Assert
    assertEq(policyManager.promptVersion(), expectedVersion);
    assertEq(mtToken.balanceOf(user), expectedUserMint);
    assertEq(mtToken.balanceOf(dev), expectedDevMint);
  }

  function testFuzz_EmitsPromptEditedEvent(uint256 _start, uint256 _end, string memory _replacement)
    public
  {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Create replacement of exact range length
    uint256 rangeLength = _end - _start;
    if (rangeLength == 0) {
      _replacement = "";
    } else {
      bytes memory newReplacement = new bytes(rangeLength);
      for (uint256 i = 0; i < rangeLength; i++) {
        newReplacement[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
      }
      _replacement = string(newReplacement);
    }

    uint256 replacementLength = rangeLength;
    uint256 expectedChanged = (replacementLength + 9) / 10;
    uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
    uint256 expectedUserMint = expectedChanged * policyManager.MT_PER_10CHARS_USER();
    uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10_000;

    _fundUserAndApprove(expectedCostUSDC + 1e6);

    // ---- Act & Assert
    vm.expectEmit(true, true, true, true);
    emit PolicyManager.PromptEdited(
      user,
      _start,
      _end,
      replacementLength,
      expectedChanged,
      expectedCostUSDC,
      expectedUserMint,
      expectedDevMint,
      policyManager.promptVersion() + 1
    );

    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);
  }

  function testFuzz_RevertIf_InvalidEditRange(
    uint256 _start,
    uint256 _end,
    string memory _replacement
  ) public {
    // ---- Arrange
    _fundUserAndApprove(1000e6);

    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;

    // Make start > end or end > promptLength
    _start = bound(_start, 0, type(uint256).max);
    _end = bound(_end, 0, type(uint256).max);
    vm.assume(_start > _end || _end > promptLength);

    // ---- Act & Assert
    vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);
  }

  function testFuzz_RevertIf_InvalidReplacementLength(
    uint256 _start,
    uint256 _end,
    string memory _replacement
  ) public {
    // ---- Arrange
    _fundUserAndApprove(1000e6);

    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Make replacement length not match the range
    bytes memory replacementBytes = bytes(_replacement);
    uint256 replacementLength = replacementBytes.length;
    vm.assume(replacementLength != _end - _start);

    // ---- Act & Assert
    vm.expectRevert(PolicyManager.PolicyManager__InvalidReplacementLength.selector);
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);
  }

  function testFuzz_RevertIf_InsufficientUSDCBalance(
    uint256 _start,
    uint256 _end,
    string memory _replacement
  ) public {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Create replacement of exact range length
    uint256 rangeLength = _end - _start;
    // Ensure we have at least 1 character change to test insufficient balance
    if (rangeLength == 0) {
      rangeLength = 1;
      _end = _start + 1;
      vm.assume(_end <= promptLength);
    }

    bytes memory newReplacement = new bytes(rangeLength);
    for (uint256 i = 0; i < rangeLength; i++) {
      newReplacement[i] = bytes1(uint8(65 + (i % 26)));
    }
    _replacement = string(newReplacement);

    uint256 expectedChanged = (rangeLength + 9) / 10;
    uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();

    // Only test if cost is greater than 0
    vm.assume(expectedCostUSDC > 0);

    // Give user less USDC than needed
    usdc.mint(user, expectedCostUSDC - 1);
    vm.prank(user);
    usdc.approve(address(policyManager), type(uint256).max);

    // ---- Act & Assert
    // Note: OpenZeppelin ERC20 reverts on insufficient balance, so we expect that revert
    // rather than PolicyManager__TransferFailed
    vm.expectRevert(); // Will be ERC20InsufficientBalance
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);
  }

  function testFuzz_AppliesEditCorrectly(uint256 _start, uint256 _end, string memory _replacement)
    public
  {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Create replacement of exact range length
    uint256 rangeLength = _end - _start;
    bytes memory newReplacement = new bytes(rangeLength);
    for (uint256 i = 0; i < rangeLength; i++) {
      newReplacement[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
    }
    _replacement = string(newReplacement);

    // Calculate expected result
    bytes memory promptBytes = bytes(currentPrompt);
    bytes memory replacementBytes = bytes(_replacement);
    bytes memory expectedResult = new bytes(promptLength - rangeLength + replacementBytes.length);

    // Copy part before edit
    for (uint256 i = 0; i < _start; i++) {
      expectedResult[i] = promptBytes[i];
    }

    // Copy replacement
    for (uint256 i = 0; i < replacementBytes.length; i++) {
      expectedResult[_start + i] = replacementBytes[i];
    }

    // Copy part after edit
    for (uint256 i = _end; i < promptLength; i++) {
      expectedResult[_start + replacementBytes.length + (i - _end)] = promptBytes[i];
    }

    uint256 expectedChanged = (replacementBytes.length + 9) / 10;
    uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
    _fundUserAndApprove(expectedCostUSDC + 1e6);

    // ---- Act
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);

    // ---- Assert
    assertEq(policyManager.prompt(), string(expectedResult));
  }

  function test_EditsPromptWithZeroRangeLength() public {
    // ---- Arrange
    _fundUserAndApprove(1e6); // Fund user with 1 USDC
    uint256 start = 5;
    uint256 end = 5; // Zero range length
    string memory replacement = ""; // Empty replacement

    uint256 versionBefore = policyManager.promptVersion();

    // ---- Act
    vm.prank(user);
    policyManager.editPrompt(start, end, replacement);

    // ---- Assert
    assertEq(policyManager.promptVersion(), versionBefore + 1);
    // No tokens should be minted for zero length change
    assertEq(mtToken.balanceOf(user), 0);
    assertEq(mtToken.balanceOf(dev), 0);
  }

  function test_EditsPromptWithExactCostCalculation() public {
    // ---- Arrange
    // Test with exactly 10 characters to verify cost calculation
    _fundUserAndApprove(1_000_000); // 1 USDC
    uint256 start = 0;
    uint256 end = 10;
    string memory replacement = "ABCDEFGHIJ"; // Exactly 10 characters

    // ---- Act
    vm.prank(user);
    policyManager.editPrompt(start, end, replacement);

    // ---- Assert
    // 10 characters = 1 unit = 1 USDC cost, 0.1 MT to user, 0.02 MT to dev
    assertEq(mtToken.balanceOf(user), 100_000_000_000_000_000); // 0.1 MT
    assertEq(mtToken.balanceOf(dev), 20_000_000_000_000_000); // 0.02 MT
  }
}

contract GetPrompt is PolicyManagerTest {
  address user;

  function setUp() public override {
    super.setUp();
    user = makeAddr("User");
    vm.label(user, "User");
  }

  function _fundUserAndApprove(uint256 amount) internal {
    usdc.mint(user, amount);
    vm.prank(user);
    usdc.approve(address(policyManager), type(uint256).max);
  }

  function test_ReturnsCurrentPromptAndVersion() public view {
    (string memory prompt, uint256 version) = policyManager.getPrompt();
    assertEq(prompt, initialPrompt);
    assertEq(version, 1);
  }

  function testFuzz_ReturnsUpdatedPromptAfterEdit(
    uint256 _start,
    uint256 _end,
    string memory _replacement
  ) public {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    // Create replacement of exact range length
    uint256 rangeLength = _end - _start;
    bytes memory newReplacement = new bytes(rangeLength);
    for (uint256 i = 0; i < rangeLength; i++) {
      newReplacement[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
    }
    _replacement = string(newReplacement);

    uint256 expectedChanged = (rangeLength + 9) / 10;
    uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
    _fundUserAndApprove(expectedCostUSDC + 1e6);

    // ---- Act
    vm.prank(user);
    policyManager.editPrompt(_start, _end, _replacement);

    // ---- Assert
    (string memory newPrompt, uint256 newVersion) = policyManager.getPrompt();
    assertEq(newVersion, 2);
    assertTrue(bytes(newPrompt).length > 0);
  }
}

contract GetPromptSlice is PolicyManagerTest {
  function testFuzz_ReturnsCorrectSlice(uint256 _start, uint256 _end) public view {
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;
    (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

    string memory slice = policyManager.getPromptSlice(_start, _end);

    bytes memory promptBytes = bytes(currentPrompt);
    bytes memory expectedSlice = new bytes(_end - _start);

    for (uint256 i = _start; i < _end; i++) {
      expectedSlice[i - _start] = promptBytes[i];
    }

    assertEq(slice, string(expectedSlice));
  }

  function test_ReturnsEmptySliceForZeroRange() public view {
    // ---- Act
    string memory slice = policyManager.getPromptSlice(5, 5);

    // ---- Assert
    assertEq(slice, "");
  }

  function test_ReturnsFullPromptSlice() public view {
    // ---- Arrange
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;

    // ---- Act
    string memory slice = policyManager.getPromptSlice(0, promptLength);

    // ---- Assert
    assertEq(slice, currentPrompt);
  }

  function testFuzz_RevertIf_InvalidSliceRange(uint256 _start, uint256 _end) public {
    string memory currentPrompt = policyManager.prompt();
    uint256 promptLength = bytes(currentPrompt).length;

    // Make start > end or end > promptLength
    _start = bound(_start, 0, type(uint256).max);
    _end = bound(_end, 0, type(uint256).max);
    vm.assume(_start > _end || _end > promptLength);

    vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
    policyManager.getPromptSlice(_start, _end);
  }
}

contract PreviewEditCost is PolicyManagerTest {
  function testFuzz_CalculatesCorrectCosts(uint256 _changed) public view {
    _changed = _boundToReasonableCost(_changed);

    (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(_changed);

    uint256 expectedCostUSDC = _changed * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
    uint256 expectedUserMint = _changed * policyManager.MT_PER_10CHARS_USER();
    uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10_000;

    assertEq(costUSDC, expectedCostUSDC);
    assertEq(userMint, expectedUserMint);
    assertEq(devMint, expectedDevMint);
  }

  function test_CalculatesCostsForSpecificValues() public view {
    (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(1);

    assertEq(costUSDC, 1_000_000); // 1 USDC
    assertEq(userMint, 100_000_000_000_000_000); // 0.1 MT
    assertEq(devMint, 20_000_000_000_000_000); // 0.02 MT (20% of 0.1)
  }

  function test_CalculatesCostsForMultipleUnits() public view {
    (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(5);

    assertEq(costUSDC, 5_000_000); // 5 USDC
    assertEq(userMint, 500_000_000_000_000_000); // 0.5 MT
    assertEq(devMint, 100_000_000_000_000_000); // 0.1 MT (20% of 0.5)
  }
}

contract PromptVersion is PolicyManagerTest {
  address user;

  function setUp() public override {
    super.setUp();
    user = makeAddr("User");
    vm.label(user, "User");
  }

  function _fundUserAndApprove(uint256 amount) internal {
    usdc.mint(user, amount);
    vm.prank(user);
    usdc.approve(address(policyManager), type(uint256).max);
  }

  function test_IncrementsVersionOnEachEdit() public {
    // ---- Arrange
    _fundUserAndApprove(1000e6);
    uint256 initialVersion = policyManager.promptVersion();

    // ---- Act & Assert
    // First edit
    vm.prank(user);
    policyManager.editPrompt(0, 1, "X");
    assertEq(policyManager.promptVersion(), initialVersion + 1);

    // Second edit
    vm.prank(user);
    policyManager.editPrompt(1, 2, "Y");
    assertEq(policyManager.promptVersion(), initialVersion + 2);

    // Third edit
    vm.prank(user);
    policyManager.editPrompt(2, 3, "Z");
    assertEq(policyManager.promptVersion(), initialVersion + 3);
  }

  function testFuzz_IncrementsVersionOnMultipleEdits(uint256 _editCount) public {
    // ---- Arrange
    _editCount = bound(_editCount, 1, 10);
    _fundUserAndApprove(1000e6);
    uint256 initialVersion = policyManager.promptVersion();

    // ---- Act & Assert
    for (uint256 i = 0; i < _editCount; i++) {
      vm.prank(user);
      policyManager.editPrompt(i, i + 1, "X");
      assertEq(policyManager.promptVersion(), initialVersion + i + 1);
    }
  }
}

contract Constants is PolicyManagerTest {
  function test_EditPricePer10CharsUSDC() public view {
    assertEq(policyManager.EDIT_PRICE_PER_10_CHARS_USDC(), 1_000_000);
  }

  function test_MtPer10charsUser() public view {
    assertEq(policyManager.MT_PER_10CHARS_USER(), 100_000_000_000_000_000);
  }

  function test_DevBps() public view {
    assertEq(policyManager.DEV_BPS(), 2000);
  }

  function test_MinterRoleConstant() public view {
    // Test that the MINTER_ROLE constant matches what's expected
    bytes32 expectedRole = keccak256("MINTER_ROLE");
    assertEq(MINTER_ROLE, expectedRole);
  }
}
