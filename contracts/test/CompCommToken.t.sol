// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {CompCommToken} from "src/CompCommToken.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";
import {IERC20Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";

contract CompCommTokenTest is Test {
  CompCommToken token;
  address admin;
  address minter;
  address burner;
  address pauser;
  address user1;
  address user2;

  // Role constants
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

  function setUp() public virtual {
    admin = makeAddr("admin");
    minter = makeAddr("minter");
    burner = makeAddr("burner");
    pauser = makeAddr("pauser");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");

    vm.label(admin, "Admin");
    vm.label(minter, "Minter");
    vm.label(burner, "Burner");
    vm.label(pauser, "Pauser");
    vm.label(user1, "User1");
    vm.label(user2, "User2");

    token = new CompCommToken(admin);

    // Grant roles
    vm.startPrank(admin);
    token.grantRole(MINTER_ROLE, minter);
    token.grantRole(BURNER_ROLE, burner);
    token.grantRole(PAUSER_ROLE, pauser);
    vm.stopPrank();
  }

  function _boundMintAmount(uint256 _amount) internal pure returns (uint256) {
    return bound(_amount, 1, type(uint96).max);
  }

  function _assumeSafeAddress(address _address) internal view {
    vm.assume(_address != address(0));
    vm.assume(_address.code.length == 0);
  }

  function _assumeNotAdmin(address _address) internal view {
    vm.assume(_address != admin);
  }

  function _assumeNotMinter(address _address) internal view {
    vm.assume(_address != minter && _address != admin);
  }

  function _assumeNotBurner(address _address) internal view {
    vm.assume(_address != burner && _address != admin);
  }

  function _assumeNotPauser(address _address) internal view {
    vm.assume(_address != pauser && _address != admin);
  }

  function _mintToUser(address to, uint256 amount) internal {
    vm.prank(minter);
    token.mint(to, amount);
  }
}

contract Constructor is CompCommTokenTest {
  function test_SetsCorrectNameAndSymbol() public view {
    assertEq(token.name(), "CompComm Management Token");
    assertEq(token.symbol(), "MT");
  }

  function test_SetsCorrectDecimals() public view {
    assertEq(token.decimals(), 18);
  }

  function test_SetsAdminRole() public view {
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
  }

  function test_InitialSupplyIsZero() public view {
    assertEq(token.totalSupply(), 0);
  }

  function test_GrantsDefaultAdminRoleToAdmin() public view {
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
  }

  function testFuzz_SetsAdminToArbitraryAddress(address _admin) public {
    _assumeSafeAddress(_admin);

    CompCommToken _token = new CompCommToken(_admin);

    assertTrue(_token.hasRole(DEFAULT_ADMIN_ROLE, _admin));
    assertEq(_token.name(), "CompComm Management Token");
    assertEq(_token.symbol(), "MT");
  }

  function test_RevertIf_AdminIsZeroAddress() public {
    vm.expectRevert(CompCommToken.CompCommToken__InvalidMintAddress.selector);
    new CompCommToken(address(0));
  }
}

contract Mint is CompCommTokenTest {
  function testFuzz_MintsTokensToAddress(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    uint256 balanceBefore = token.balanceOf(_to);
    uint256 totalSupplyBefore = token.totalSupply();

    // ---- Act
    vm.prank(minter);
    token.mint(_to, _amount);

    // ---- Assert
    assertEq(token.balanceOf(_to), balanceBefore + _amount);
    assertEq(token.totalSupply(), totalSupplyBefore + _amount);
  }

  function testFuzz_EmitsTokensMintedEvent(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit CompCommToken.TokensMinted(_to, _amount);

    // ---- Act
    vm.prank(minter);
    token.mint(_to, _amount);
  }

  function testFuzz_EmitsTransferEvent(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(address(0), _to, _amount);

    // ---- Act
    vm.prank(minter);
    token.mint(_to, _amount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveMinterRole(
    address _caller,
    address _to,
    uint256 _amount
  ) public {
    _assumeNotMinter(_caller);
    _assumeSafeAddress(_to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange & Assert
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, MINTER_ROLE
      )
    );

    // ---- Act
    vm.prank(_caller);
    token.mint(_to, _amount);
  }

  function testFuzz_RevertIf_ToAddressIsZero(uint256 _amount) public {
    _amount = _boundMintAmount(_amount);

    // ---- Arrange & Assert
    vm.expectRevert(CompCommToken.CompCommToken__InvalidMintAddress.selector);

    // ---- Act
    vm.prank(minter);
    token.mint(address(0), _amount);
  }

  function test_AdminCanGrantMinterRoleAndMint() public {
    // ---- Arrange
    address to = user1;
    uint256 amount = 1000 ether;

    // Admin grants themselves minter role
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, admin);

    // ---- Act
    vm.prank(admin);
    token.mint(to, amount);

    // ---- Assert
    assertEq(token.balanceOf(to), amount);
  }
}

contract BurnFrom is CompCommTokenTest {
  function testFuzz_BurnsTokensFromAccountWithSufficientBalance(
    address _account,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    _assumeSafeAddress(_account);
    _mintAmount = _boundMintAmount(_mintAmount);
    _burnAmount = bound(_burnAmount, 1, _mintAmount);

    // ---- Arrange
    _mintToUser(_account, _mintAmount);
    // Give burner approval to burn from account
    vm.prank(_account);
    token.approve(burner, _mintAmount);

    uint256 balanceBefore = token.balanceOf(_account);
    uint256 totalSupplyBefore = token.totalSupply();

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _burnAmount);

    // ---- Assert
    assertEq(token.balanceOf(_account), balanceBefore - _burnAmount);
    assertEq(token.totalSupply(), totalSupplyBefore - _burnAmount);
  }

  function testFuzz_EmitsTokensBurnedEvent(address _account, uint256 _amount) public {
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_account, _amount);
    vm.prank(_account);
    token.approve(burner, _amount);

    vm.expectEmit(true, true, true, true);
    emit CompCommToken.TokensBurned(_account, _amount);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);
  }

  function testFuzz_EmitsTransferEvent(address _account, uint256 _amount) public {
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_account, _amount);
    vm.prank(_account);
    token.approve(burner, _amount);

    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(_account, address(0), _amount);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);
  }

  function testFuzz_BurnsFromAccountWithApproval(address _account, uint256 _amount) public {
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_account, _amount);
    vm.prank(_account);
    token.approve(burner, _amount);

    uint256 balanceBefore = token.balanceOf(_account);
    uint256 allowanceBefore = token.allowance(_account, burner);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);

    // ---- Assert
    assertEq(token.balanceOf(_account), balanceBefore - _amount);
    assertEq(token.allowance(_account, burner), allowanceBefore - _amount);
  }

  function testFuzz_BurnsFromSelfWithoutApproval(uint256 _amount) public {
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    // First, grant burner role to user1 for this test
    vm.prank(admin);
    token.grantRole(BURNER_ROLE, user1);

    _mintToUser(user1, _amount);
    uint256 balanceBefore = token.balanceOf(user1);

    // ---- Act
    vm.prank(user1);
    token.burnFrom(user1, _amount);

    // ---- Assert
    assertEq(token.balanceOf(user1), balanceBefore - _amount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveBurnerRole(
    address _caller,
    address _account,
    uint256 _amount
  ) public {
    _assumeNotBurner(_caller);
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_account, _amount);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, BURNER_ROLE
      )
    );

    // ---- Act
    vm.prank(_caller);
    token.burnFrom(_account, _amount);
  }

  function test_RevertIf_AccountIsZeroAddress() public {
    // ---- Arrange & Assert
    vm.expectRevert(CompCommToken.CompCommToken__InvalidBurnAddress.selector);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(address(0), 100 ether);
  }

  function testFuzz_RevertIf_InsufficientBalance(address _account, uint256 _amount) public {
    _assumeSafeAddress(_account);
    _amount = bound(_amount, 2, type(uint96).max); // Ensure _amount is at least 2

    // ---- Arrange
    uint256 smallAmount = _amount - 1; // Give them less than they try to burn
    _mintToUser(_account, smallAmount);
    vm.prank(_account);
    token.approve(burner, _amount); // Approve the full amount

    vm.expectRevert(CompCommToken.CompCommToken__InsufficientBalance.selector);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);
  }

  function testFuzz_RevertIf_InsufficientAllowance(
    address _account,
    uint256 _amount,
    uint256 _approval
  ) public {
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);
    _approval = bound(_approval, 0, _amount - 1);

    // ---- Arrange
    _mintToUser(_account, _amount);
    vm.prank(_account);
    token.approve(burner, _approval);

    vm.expectRevert(CompCommToken.CompCommToken__InsufficientAllowance.selector);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);
  }
}

contract Pause is CompCommTokenTest {
  function test_PausesToken() public {
    // ---- Arrange
    assertFalse(token.paused());

    // ---- Act
    vm.prank(pauser);
    token.pause();

    // ---- Assert
    assertTrue(token.paused());
  }

  function test_EmitsTransfersPausedEvent() public {
    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit CompCommToken.TransfersPaused(pauser);

    // ---- Act
    vm.prank(pauser);
    token.pause();
  }

  function test_EmitsPausedEvent() public {
    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit Pausable.Paused(pauser);

    // ---- Act
    vm.prank(pauser);
    token.pause();
  }

  function testFuzz_RevertIf_CallerDoesNotHavePauserRole(address _caller) public {
    _assumeNotPauser(_caller);

    // ---- Arrange & Assert
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, PAUSER_ROLE
      )
    );

    // ---- Act
    vm.prank(_caller);
    token.pause();
  }

  function test_AdminCanGrantPauserRoleAndPause() public {
    // ---- Arrange
    vm.prank(admin);
    token.grantRole(PAUSER_ROLE, admin);

    // ---- Act
    vm.prank(admin);
    token.pause();

    // ---- Assert
    assertTrue(token.paused());
  }
}

contract Unpause is CompCommTokenTest {
  function setUp() public override {
    super.setUp();
    // Start with token paused
    vm.prank(pauser);
    token.pause();
  }

  function test_UnpausesToken() public {
    // ---- Arrange
    assertTrue(token.paused());

    // ---- Act
    vm.prank(pauser);
    token.unpause();

    // ---- Assert
    assertFalse(token.paused());
  }

  function test_EmitsTransfersUnpausedEvent() public {
    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit CompCommToken.TransfersUnpaused(pauser);

    // ---- Act
    vm.prank(pauser);
    token.unpause();
  }

  function test_EmitsUnpausedEvent() public {
    // ---- Arrange & Assert
    vm.expectEmit(true, true, true, true);
    emit Pausable.Unpaused(pauser);

    // ---- Act
    vm.prank(pauser);
    token.unpause();
  }

  function testFuzz_RevertIf_CallerDoesNotHavePauserRole(address _caller) public {
    _assumeNotPauser(_caller);

    // ---- Arrange & Assert
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, _caller, PAUSER_ROLE
      )
    );

    // ---- Act
    vm.prank(_caller);
    token.unpause();
  }

  function test_AdminCanGrantPauserRoleAndUnpause() public {
    // ---- Arrange
    vm.prank(admin);
    token.grantRole(PAUSER_ROLE, admin);

    // ---- Act
    vm.prank(admin);
    token.unpause();

    // ---- Assert
    assertFalse(token.paused());
  }
}

contract Update is CompCommTokenTest {
  function testFuzz_AllowsTransfersWhenNotPaused(address _from, address _to, uint256 _amount)
    public
  {
    _assumeSafeAddress(_from);
    _assumeSafeAddress(_to);
    vm.assume(_from != _to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_from, _amount);
    assertFalse(token.paused());

    uint256 fromBalanceBefore = token.balanceOf(_from);
    uint256 toBalanceBefore = token.balanceOf(_to);

    // ---- Act
    vm.prank(_from);
    token.transfer(_to, _amount);

    // ---- Assert
    assertEq(token.balanceOf(_from), fromBalanceBefore - _amount);
    assertEq(token.balanceOf(_to), toBalanceBefore + _amount);
  }

  function testFuzz_RevertIf_TransferWhenPaused(address _from, address _to, uint256 _amount) public {
    _assumeSafeAddress(_from);
    _assumeSafeAddress(_to);
    vm.assume(_from != _to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_from, _amount);
    vm.prank(pauser);
    token.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);

    // ---- Act
    vm.prank(_from);
    token.transfer(_to, _amount);
  }

  function testFuzz_RevertIf_MintWhenPaused(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    vm.prank(pauser);
    token.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);

    // ---- Act
    vm.prank(minter);
    token.mint(_to, _amount);
  }

  function testFuzz_RevertIf_BurnWhenPaused(address _account, uint256 _amount) public {
    _assumeSafeAddress(_account);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    _mintToUser(_account, _amount);
    vm.prank(_account);
    token.approve(burner, _amount);
    vm.prank(pauser);
    token.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);

    // ---- Act
    vm.prank(burner);
    token.burnFrom(_account, _amount);
  }

  function testFuzz_AllowsApprovalWhenPaused(address _owner, address _spender, uint256 _amount)
    public
  {
    _assumeSafeAddress(_owner);
    _assumeSafeAddress(_spender);
    vm.assume(_owner != _spender);
    _amount = _boundMintAmount(_amount);

    // ---- Arrange
    vm.prank(pauser);
    token.pause();

    // ---- Act (approvals should still work when paused)
    vm.prank(_owner);
    token.approve(_spender, _amount);

    // ---- Assert
    assertEq(token.allowance(_owner, _spender), _amount);
  }
}
