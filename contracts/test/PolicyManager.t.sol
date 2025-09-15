// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyManager} from "src/PolicyManager.sol";
import {CompCommToken} from "src/CompCommToken.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

/// @title PolicyManagerTest
/// @notice Test suite for PolicyManager contract following ScopeLift testing standards.
contract PolicyManagerTest is Test {
    PolicyManager policyManager;
    CompCommToken mtToken;
    MockERC20 usdc;
    address admin;
    address dev;
    string initialPrompt;

    function setUp() public virtual {
        admin = makeAddr("Admin");
        dev = makeAddr("Dev");
        initialPrompt = "Initial investment policy: Invest in blue chip stocks and bonds.";

        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vm.label(address(usdc), "USDC");

        // Deploy MT token
        vm.prank(admin);
        mtToken = new CompCommToken(admin);
        vm.label(address(mtToken), "MT Token");

        // Deploy PolicyManager
        policyManager = new PolicyManager(address(usdc), address(mtToken), dev, initialPrompt);
        vm.label(address(policyManager), "PolicyManager");

        // Grant MINTER_ROLE to PolicyManager
        vm.prank(admin);
        mtToken.grantRole(mtToken.MINTER_ROLE(), address(policyManager));
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

    function testFuzz_RevertIf_UsdcAddressIsZero(address _mtToken, address _dev, string memory _initialPrompt) public {
        _assumeSafeAddress(_mtToken);
        _assumeSafeAddress(_dev);

        vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
        new PolicyManager(address(0), _mtToken, _dev, _initialPrompt);
    }

    function testFuzz_RevertIf_MtTokenAddressIsZero(address _usdc, address _dev, string memory _initialPrompt) public {
        _assumeSafeAddress(_usdc);
        _assumeSafeAddress(_dev);

        vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
        new PolicyManager(_usdc, address(0), _dev, _initialPrompt);
    }

    function testFuzz_RevertIf_DevAddressIsZero(address _usdc, address _mtToken, string memory _initialPrompt) public {
        _assumeSafeAddress(_usdc);
        _assumeSafeAddress(_mtToken);

        vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
        new PolicyManager(_usdc, _mtToken, address(0), _initialPrompt);
    }
}

contract EditPrompt is PolicyManagerTest {
    function setUp() public override {
        super.setUp();

        // Fund user with USDC and approve PolicyManager
        address user = makeAddr("User");
        usdc.mint(user, 1000e6); // 1000 USDC
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);
    }

    function testFuzz_EditsPromptWithValidRange(uint256 _start, uint256 _end, string memory _replacement) public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);
        _replacement = string(abi.encodePacked(_replacement, "x")); // Ensure non-empty
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;

        // Adjust end to match replacement length
        _end = _start + replacementLength;
        vm.assume(_end <= promptLength);

        uint256 expectedVersion = policyManager.promptVersion() + 1;
        uint256 expectedChanged = (replacementLength + 9) / 10;
        uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
        uint256 expectedUserMint = expectedChanged * policyManager.MT_PER_10CHARS_USER();
        uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10000;

        vm.prank(user);
        policyManager.editPrompt(_start, _end, _replacement);

        // Check state changes
        assertEq(policyManager.promptVersion(), expectedVersion);
        assertEq(usdc.balanceOf(user), 1000e6 - expectedCostUSDC);
        assertEq(usdc.balanceOf(address(policyManager)), expectedCostUSDC);
        assertEq(mtToken.balanceOf(user), expectedUserMint);
        assertEq(mtToken.balanceOf(dev), expectedDevMint);
    }

    function testFuzz_EmitsPromptEditedEvent(uint256 _start, uint256 _end, string memory _replacement) public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);
        _replacement = string(abi.encodePacked(_replacement, "x"));
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;
        _end = _start + replacementLength;
        vm.assume(_end <= promptLength);

        uint256 expectedChanged = (replacementLength + 9) / 10;
        uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
        uint256 expectedUserMint = expectedChanged * policyManager.MT_PER_10CHARS_USER();
        uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10000;

        vm.prank(user);
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
        policyManager.editPrompt(_start, _end, _replacement);
    }

    function testFuzz_RevertIf_InvalidEditRange(uint256 _start, uint256 _end, string memory _replacement) public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;

        // Make start > end or end > promptLength
        _start = bound(_start, 0, type(uint256).max);
        _end = bound(_end, 0, type(uint256).max);
        vm.assume(_start > _end || _end > promptLength);

        vm.prank(user);
        vm.expectRevert(PolicyManager.PolicyManager__InvalidEditRange.selector);
        policyManager.editPrompt(_start, _end, _replacement);
    }

    function testFuzz_RevertIf_InvalidReplacementLength(uint256 _start, uint256 _end, string memory _replacement)
        public
    {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);

        // Make replacement length not match the range
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;
        vm.assume(replacementLength != _end - _start);

        vm.prank(user);
        vm.expectRevert(PolicyManager.PolicyManager__InvalidReplacementLength.selector);
        policyManager.editPrompt(_start, _end, _replacement);
    }

    function testFuzz_RevertIf_InsufficientUSDCBalance(uint256 _start, uint256 _end, string memory _replacement)
        public
    {
        address user = makeAddr("User");

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);
        _replacement = string(abi.encodePacked(_replacement, "x"));
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;
        _end = _start + replacementLength;
        vm.assume(_end <= promptLength);

        uint256 expectedChanged = (replacementLength + 9) / 10;
        uint256 expectedCostUSDC = expectedChanged * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();

        // Give user less USDC than needed
        usdc.mint(user, expectedCostUSDC - 1);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        vm.prank(user);
        vm.expectRevert(PolicyManager.PolicyManager__TransferFailed.selector);
        policyManager.editPrompt(_start, _end, _replacement);
    }

    function testFuzz_AppliesEditCorrectly(uint256 _start, uint256 _end, string memory _replacement) public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);
        _replacement = string(abi.encodePacked(_replacement, "x"));
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;
        _end = _start + replacementLength;
        vm.assume(_end <= promptLength);

        // Calculate expected result
        bytes memory promptBytes = bytes(currentPrompt);
        bytes memory expectedResult = new bytes(promptLength - (_end - _start) + replacementLength);

        // Copy part before edit
        for (uint256 i = 0; i < _start; i++) {
            expectedResult[i] = promptBytes[i];
        }

        // Copy replacement
        for (uint256 i = 0; i < replacementLength; i++) {
            expectedResult[_start + i] = replacementBytes[i];
        }

        // Copy part after edit
        for (uint256 i = _end; i < promptLength; i++) {
            expectedResult[_start + replacementLength + (i - _end)] = promptBytes[i];
        }

        vm.prank(user);
        policyManager.editPrompt(_start, _end, _replacement);

        assertEq(policyManager.prompt(), string(expectedResult));
    }
}

contract GetPrompt is PolicyManagerTest {
    function test_ReturnsCurrentPromptAndVersion() public view {
        (string memory prompt, uint256 version) = policyManager.getPrompt();
        assertEq(prompt, initialPrompt);
        assertEq(version, 1);
    }

    function testFuzz_ReturnsUpdatedPromptAfterEdit(uint256 _start, uint256 _end, string memory _replacement) public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        string memory currentPrompt = policyManager.prompt();
        uint256 promptLength = bytes(currentPrompt).length;
        (_start, _end) = _boundToReasonableEditRange(_start, _end, promptLength);
        _replacement = string(abi.encodePacked(_replacement, "x"));
        bytes memory replacementBytes = bytes(_replacement);
        uint256 replacementLength = replacementBytes.length;
        _end = _start + replacementLength;
        vm.assume(_end <= promptLength);

        vm.prank(user);
        policyManager.editPrompt(_start, _end, _replacement);

        (string memory newPrompt, uint256 newVersion) = policyManager.getPrompt();
        assertEq(newVersion, 2);
        assertTrue(bytes(newPrompt).length > 0);
    }
}

contract GetPromptSlice is PolicyManagerTest {
    function testFuzz_ReturnsCorrectSlice(uint256 _start, uint256 _end) public {
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
    function testFuzz_CalculatesCorrectCosts(uint256 _changed) public {
        _changed = _boundToReasonableCost(_changed);

        (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(_changed);

        uint256 expectedCostUSDC = _changed * policyManager.EDIT_PRICE_PER_10_CHARS_USDC();
        uint256 expectedUserMint = _changed * policyManager.MT_PER_10CHARS_USER();
        uint256 expectedDevMint = (expectedUserMint * policyManager.DEV_BPS()) / 10000;

        assertEq(costUSDC, expectedCostUSDC);
        assertEq(userMint, expectedUserMint);
        assertEq(devMint, expectedDevMint);
    }

    function test_CalculatesCostsForSpecificValues() public {
        (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(1);

        assertEq(costUSDC, 1_000_000); // 1 USDC
        assertEq(userMint, 100_000_000_000_000_000); // 0.1 MT
        assertEq(devMint, 20_000_000_000_000_000); // 0.02 MT (20% of 0.1)
    }

    function test_CalculatesCostsForMultipleUnits() public {
        (uint256 costUSDC, uint256 userMint, uint256 devMint) = policyManager.previewEditCost(5);

        assertEq(costUSDC, 5_000_000); // 5 USDC
        assertEq(userMint, 500_000_000_000_000_000); // 0.5 MT
        assertEq(devMint, 100_000_000_000_000_000); // 0.1 MT (20% of 0.5)
    }
}

contract PromptVersion is PolicyManagerTest {
    function test_IncrementsVersionOnEachEdit() public {
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        uint256 initialVersion = policyManager.promptVersion();

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
        address user = makeAddr("User");
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(policyManager), type(uint256).max);

        _editCount = bound(_editCount, 1, 10);
        uint256 initialVersion = policyManager.promptVersion();

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
}

/// @title MockERC20
/// @notice Mock ERC20 token for testing purposes.
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
