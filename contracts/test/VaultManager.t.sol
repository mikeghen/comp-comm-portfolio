// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";

import {VaultManager} from "src/VaultManager.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {ManagementToken} from "src/ManagementToken.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockSwapRouter} from "test/mocks/MockSwapRouter.sol";
import {MockComet} from "test/mocks/MockComet.sol";
import {MockCometRewards} from "test/mocks/MockCometRewards.sol";

contract VaultManagerTest is Test {
  VaultManager vault;
  ManagementToken mtToken;
  MockERC20 usdc;
  MockERC20 weth;
  MockSwapRouter router;
  MockComet comet;
  MockCometRewards cometRewards;

  address owner;
  address agent;
  address user;
  address admin;

  // Role constants
  bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 constant AGENT_ROLE = keccak256("AGENT_ROLE");
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

  function setUp() public virtual {
    owner = makeAddr("Owner");
    agent = makeAddr("Agent");
    user = makeAddr("User");
    admin = makeAddr("Admin");

    usdc = new MockERC20("USD Coin", "USDC", 6);
    weth = new MockERC20("Wrapped Ether", "WETH", 18);
    router = new MockSwapRouter();
    comet = new MockComet();
    cometRewards = new MockCometRewards();

    vm.prank(admin);
    mtToken = new ManagementToken(admin);
    // Grant MINTER_ROLE to admin for mint helper
    vm.prank(admin);
    mtToken.grantRole(MINTER_ROLE, admin);

    vm.prank(owner);
    vault = new VaultManager(
      address(usdc), address(weth), address(mtToken), address(router), address(cometRewards), agent
    );

    // Configure allowlists
    vm.startPrank(owner);
    vault.setAllowedAsset(address(usdc), true);
    vault.setAllowedAsset(address(weth), true);
    vault.setAllowedComet(address(comet), true);
    vault.setAssetComet(address(usdc), address(comet));
    vm.stopPrank();
  }

  function _fundVault(address token, uint256 amount) internal {
    MockERC20(token).mint(address(vault), amount);
  }

  function _mintMtTo(address to, uint256 amount) internal {
    vm.prank(admin);
    mtToken.mint(to, amount);
  }

  // --------------------
  // Helpers to reduce repetition
  // --------------------
  function _warpToPostUnlock() internal {
    vm.warp(vault.UNLOCK_TIMESTAMP() + 1);
  }

  function _swapParams(address tokenIn, address tokenOut, uint256 amountIn)
    internal
    view
    returns (ISwapRouter.ExactInputSingleParams memory)
  {
    return ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: 3000,
      recipient: address(vault),
      amountIn: amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });
  }

  function _exactInputSingleAs(address caller, address tokenIn, address tokenOut, uint256 amountIn)
    internal
  {
    vm.prank(caller);
    vault.exactInputSingle(_swapParams(tokenIn, tokenOut, amountIn));
  }

  function _supplyAs(address caller, address asset, uint256 amount) internal {
    vm.prank(caller);
    vault.supply(asset, amount);
  }

  function _withdrawAs(address caller, address asset, uint256 amount) internal {
    vm.prank(caller);
    vault.withdraw(asset, amount);
  }

  function _claimCompAs(address caller, address cometAddr, address to) internal returns (uint256) {
    vm.prank(caller);
    return vault.claimComp(cometAddr, to);
  }

  function _grantVaultBurner() internal {
    vm.prank(admin);
    mtToken.grantRole(BURNER_ROLE, address(vault));
  }

  function _mintAndApproveMt(address holder, uint256 amount) internal {
    _mintMtTo(holder, amount);
    vm.prank(holder);
    mtToken.approve(address(vault), amount);
  }

  function _enterRedemptionWithWETH(uint256 totalWeth) internal {
    _warpToPostUnlock();
    _fundVault(address(weth), totalWeth);
  }
}

contract Constructor is VaultManagerTest {
  function test_SetsConfigurationParameters() public view {
    // lockStart and unlockTimestamp
    uint256 lockStart = vault.LOCK_START();
    assertTrue(lockStart <= block.timestamp);
    assertEq(vault.UNLOCK_TIMESTAMP(), lockStart + vault.LOCK_DURATION());

    // Addresses
    assertEq(vault.USDC(), address(usdc));
    assertEq(vault.WETH(), address(weth));
    assertEq(vault.mtToken(), address(mtToken));
    assertEq(vault.UNISWAP_V3_ROUTER(), address(router));
    assertEq(vault.COMET_REWARDS(), address(cometRewards));

    // Access control
    assertEq(vault.owner(), owner);
    assertTrue(vault.hasRole(AGENT_ROLE, agent));
  }

  function test_RevertIf_ZeroAddress_USDC() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    new VaultManager(
      address(0), address(weth), address(mtToken), address(router), address(cometRewards), agent
    );
  }

  function test_RevertIf_ZeroAddress_WETH() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    new VaultManager(
      address(usdc), address(0), address(mtToken), address(router), address(cometRewards), agent
    );
  }

  function test_RevertIf_ZeroAddress_Router() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    new VaultManager(
      address(usdc), address(weth), address(mtToken), address(0), address(cometRewards), agent
    );
  }

  function test_RevertIf_ZeroAddress_CometRewards() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    new VaultManager(
      address(usdc), address(weth), address(mtToken), address(router), address(0), agent
    );
  }
}

contract SwapExactInputV3 is VaultManagerTest {
  function test_RevertIf_AmountZero() public {
    vm.expectRevert(VaultManager.VaultManager__AmountZero.selector);
    _exactInputSingleAs(owner, address(usdc), address(weth), 0);
  }

  function test_RevertIf_TokenOutNotWETH_PostUnlock() public {
    _warpToPostUnlock();
    _fundVault(address(usdc), 1e6);
    vm.expectRevert(VaultManager.VaultManager__InvalidPhase.selector);
    _exactInputSingleAs(owner, address(usdc), address(usdc), 1);
  }

  function test_SwapsInLockedPhase() public {
    // ---- Arrange
    uint256 amountIn = 1_000_000; // 1 USDC
    _fundVault(address(usdc), amountIn);

    // ---- Act
    _exactInputSingleAs(owner, address(usdc), address(weth), amountIn);

    // ---- Assert
    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(weth.balanceOf(address(vault)), amountIn * 2);
  }

  function test_EmitsSwapExecutedEvent() public {
    // ---- Arrange
    uint256 amountIn = 2_000_000;
    _fundVault(address(usdc), amountIn);

    vm.expectEmit();
    emit VaultManager.SwapExecuted(address(usdc), address(weth), amountIn, amountIn * 2);

    // ---- Act (event only)
    _exactInputSingleAs(owner, address(usdc), address(weth), amountIn);
  }

  function testFuzz_RevertIf_TokenNotAllowed(address _token) public {
    vm.assume(_token != address(usdc) && _token != address(weth) && _token != address(0));
    // ---- Arrange
    _fundVault(address(usdc), 1e6);

    // ---- Assert
    vm.expectRevert(VaultManager.VaultManager__AssetNotAllowed.selector);

    // ---- Act
    _exactInputSingleAs(owner, _token, address(weth), 1e6);
  }

  function test_RevertIf_PostUnlock_SwapNotToWETH() public {
    // ---- Arrange
    _warpToPostUnlock();
    _fundVault(address(usdc), 1e6);

    // ---- Assert
    vm.expectRevert(VaultManager.VaultManager__InvalidPhase.selector);

    // ---- Act
    _exactInputSingleAs(owner, address(usdc), address(usdc), 1e6);
  }

  function test_Allows_PostUnlock_SwapToWETH() public {
    // ---- Arrange
    _warpToPostUnlock();
    _fundVault(address(usdc), 2e6);

    // ---- Act
    _exactInputSingleAs(owner, address(usdc), address(weth), 2e6);

    // ---- Assert
    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(weth.balanceOf(address(vault)), 4e6);
  }

  function test_AgentCanSwapInLockedPhase() public {
    uint256 amountIn = 1_000_000;
    _fundVault(address(usdc), amountIn);

    _exactInputSingleAs(agent, address(usdc), address(weth), amountIn);

    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(weth.balanceOf(address(vault)), amountIn * 2);
  }

  function test_RevertIf_CallerNotAgentOrOwner_Swap() public {
    _fundVault(address(usdc), 1e6);
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    _exactInputSingleAs(user, address(usdc), address(weth), 1e6);
  }
}

contract Supply is VaultManagerTest {
  function test_RevertIf_AmountZero() public {
    vm.expectRevert(VaultManager.VaultManager__AmountZero.selector);
    _supplyAs(owner, address(usdc), 0);
  }

  function test_RevertIf_CometNotAllowedOrUnset() public {
    // remove existing mapping by setting to zero through expect revert on setAssetComet with zero
    address otherAsset = makeAddr("OtherAsset");
    vm.prank(owner);
    vault.setAllowedAsset(otherAsset, true);
    vm.expectRevert(VaultManager.VaultManager__CometNotAllowed.selector);
    _supplyAs(owner, otherAsset, 1);
  }

  function test_DepositsAssetToComet() public {
    // ---- Arrange
    uint256 amount = 5e6;
    _fundVault(address(usdc), amount);

    // ---- Act
    _supplyAs(owner, address(usdc), amount);

    // ---- Assert
    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(comet.balanceOf(address(vault)), amount);
  }

  function test_EmitsCometSuppliedEvent() public {
    // ---- Arrange
    uint256 amount = 7e6;
    _fundVault(address(usdc), amount);

    vm.expectEmit();
    emit VaultManager.CometSupplied(address(comet), address(usdc), amount);

    // ---- Act (event only)
    _supplyAs(owner, address(usdc), amount);
  }

  function testFuzz_RevertIf_AssetNotAllowed(address _asset) public {
    vm.assume(_asset != address(usdc) && _asset != address(weth) && _asset != address(0));
    _fundVault(address(usdc), 1e6);
    vm.expectRevert(VaultManager.VaultManager__AssetNotAllowed.selector);
    _supplyAs(owner, _asset, 1e6);
  }

  function test_RevertIf_CallerNotAgentOrOwner() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    _supplyAs(user, address(usdc), 1);
  }

  function test_AgentCanSupply() public {
    uint256 amount = 5e6;
    _fundVault(address(usdc), amount);

    _supplyAs(agent, address(usdc), amount);

    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(comet.balanceOf(address(vault)), amount);
  }
}

contract Withdraw is VaultManagerTest {
  function test_RevertIf_AmountZero() public {
    vm.expectRevert(VaultManager.VaultManager__AmountZero.selector);
    _withdrawAs(owner, address(usdc), 0);
  }

  function test_RevertIf_CometNotAllowedOrUnset() public {
    address otherAsset = makeAddr("OtherAsset");
    vm.prank(owner);
    vault.setAllowedAsset(otherAsset, true);
    vm.expectRevert(VaultManager.VaultManager__CometNotAllowed.selector);
    _withdrawAs(owner, otherAsset, 1);
  }

  function test_RevertIf_AssetNotAllowed() public {
    address otherAsset = makeAddr("OtherAsset_NotAllowed");
    vm.expectRevert(VaultManager.VaultManager__AssetNotAllowed.selector);
    _withdrawAs(owner, otherAsset, 1);
  }

  function test_WithdrawsAssetFromComet() public {
    // ---- Arrange
    uint256 amount = 3e6;
    _fundVault(address(usdc), amount);
    _supplyAs(owner, address(usdc), amount);

    // ---- Act
    _withdrawAs(owner, address(usdc), amount);

    // ---- Assert
    assertEq(usdc.balanceOf(address(vault)), amount);
    assertEq(comet.balanceOf(address(vault)), 0);
  }

  function test_EmitsCometWithdrawnEvent() public {
    // ---- Arrange
    uint256 amount = 4e6;
    _fundVault(address(usdc), amount);
    _supplyAs(owner, address(usdc), amount);

    vm.expectEmit();
    emit VaultManager.CometWithdrawn(address(comet), address(usdc), amount);

    // ---- Act (event only)
    _withdrawAs(owner, address(usdc), amount);
  }

  function test_AgentCanWithdraw() public {
    uint256 amount = 3e6;
    _fundVault(address(usdc), amount);
    _supplyAs(owner, address(usdc), amount);

    _withdrawAs(agent, address(usdc), amount);

    assertEq(usdc.balanceOf(address(vault)), amount);
    assertEq(comet.balanceOf(address(vault)), 0);
  }

  function test_RevertIf_CallerNotAgentOrOwner_Withdraw() public {
    uint256 amount = 1e6;
    _fundVault(address(usdc), amount);
    _supplyAs(owner, address(usdc), amount);

    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    _withdrawAs(user, address(usdc), amount);
  }
}

contract ClaimComp is VaultManagerTest {
  function test_RevertIf_InvalidToAddress() public {
    vm.prank(owner);
    vault.setAllowedComet(address(comet), true);
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    _claimCompAs(owner, address(comet), address(0));
  }

  function test_ClaimsRewards() public {
    // ---- Arrange
    uint256 expected = 42e18;
    cometRewards.setClaimAmount(address(comet), expected);

    // ---- Act
    uint256 claimed = _claimCompAs(owner, address(comet), user);

    // ---- Assert
    assertEq(claimed, expected);
  }

  function test_EmitsCompClaimedEvent() public {
    // ---- Arrange
    uint256 expected = 5e18;
    cometRewards.setClaimAmount(address(comet), expected);

    vm.expectEmit();
    emit VaultManager.CompClaimed(address(comet), user, expected);

    // ---- Act (event only)
    _claimCompAs(owner, address(comet), user);
  }

  function testFuzz_RevertIf_CometNotAllowed(address _comet, address _to) public {
    vm.assume(_comet != address(comet) && _comet != address(0));
    vm.assume(_to != address(0));
    vm.expectRevert(VaultManager.VaultManager__CometNotAllowed.selector);
    _claimCompAs(owner, _comet, _to);
  }

  function test_AgentCanClaimRewards() public {
    uint256 expected = 11e18;
    cometRewards.setClaimAmount(address(comet), expected);

    uint256 claimed = _claimCompAs(agent, address(comet), user);
    assertEq(claimed, expected);
  }

  function test_RevertIf_CallerNotAgentOrOwner_ClaimComp() public {
    cometRewards.setClaimAmount(address(comet), 1e18);
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    _claimCompAs(user, address(comet), user);
  }
}

contract GetCurrentPhase is VaultManagerTest {
  function test_ReturnsLockedBeforeUnlock() public view {
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.LOCKED));
  }

  function test_ReturnsConsolidationPostUnlockWithNonWethBalance() public {
    // ---- Arrange
    _warpToPostUnlock();
    _fundVault(address(usdc), 1e6);

    // ---- Assert
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.CONSOLIDATION));
    assertFalse(vault.isConsolidated());
  }

  function test_ReturnsRedemptionPostUnlockWhenConsolidated() public {
    // ---- Arrange
    _warpToPostUnlock();
    // no non-WETH balances and no comet position

    // ---- Assert
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.REDEMPTION));
    assertTrue(vault.isConsolidated());
  }

  function test_ReturnsConsolidationPostUnlockWithOpenCometPosition() public {
    uint256 amount = 1e6;

    _fundVault(address(usdc), amount);
    _supplyAs(owner, address(usdc), amount);
    _warpToPostUnlock();

    assertEq(usdc.balanceOf(address(vault)), 0);
    assertEq(comet.balanceOf(address(vault)), amount);
    assertEq(uint256(vault.getCurrentPhase()), uint256(VaultManager.Phase.CONSOLIDATION));
    assertFalse(vault.isConsolidated());
  }
}

contract RedeemWETH is VaultManagerTest {
  function test_RevertIf_AmountZero() public {
    _warpToPostUnlock();
    vm.expectRevert(VaultManager.VaultManager__AmountZero.selector);
    vault.redeemWETH(0, user);
  }

  function test_RevertIf_InvalidToAddress() public {
    _warpToPostUnlock();
    _mintAndApproveMt(user, 1 ether);
    _grantVaultBurner();
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(user);
    vault.redeemWETH(1 ether, address(0));
  }

  function setUp() public override {
    VaultManagerTest.setUp();
    // Grant burner role to the vault for redemption
    vm.prank(admin);
    mtToken.grantRole(BURNER_ROLE, address(vault));
  }

  function test_RedeemsProRataWETHInRedemptionPhase() public {
    // ---- Arrange
    uint256 totalWeth = 100 ether;
    _enterRedemptionWithWETH(totalWeth);

    uint256 userMt = 10 ether;
    _mintAndApproveMt(user, userMt);

    uint256 totalSupply = mtToken.totalSupply();
    uint256 expectedWeth = (totalWeth * userMt) / totalSupply;

    // ---- Act
    vm.prank(user);
    vault.redeemWETH(userMt, user);

    // ---- Assert
    assertEq(weth.balanceOf(user), expectedWeth);
    assertEq(weth.balanceOf(address(vault)), totalWeth - expectedWeth);
    assertEq(mtToken.balanceOf(user), 0);
  }

  function test_EmitsRedeemedEvent() public {
    // ---- Arrange
    uint256 totalWeth = 10 ether;
    _enterRedemptionWithWETH(totalWeth);

    uint256 userMt = 1 ether;
    _mintAndApproveMt(user, userMt);

    uint256 expectedWeth = (totalWeth * userMt) / mtToken.totalSupply();

    vm.expectEmit();
    emit VaultManager.Redeemed(user, user, userMt, expectedWeth);

    // ---- Act (event only)
    vm.prank(user);
    vault.redeemWETH(userMt, user);
  }

  function test_RevertIf_NotInRedemptionPhase() public {
    // ---- Arrange
    _fundVault(address(weth), 10 ether);
    _mintAndApproveMt(user, 1 ether);

    vm.expectRevert(VaultManager.VaultManager__InvalidPhase.selector);

    // ---- Act
    vm.prank(user);
    vault.redeemWETH(1 ether, user);
  }
}

contract SetAllowedAsset is VaultManagerTest {
  function test_RevertIf_TokenZeroAddress() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(owner);
    vault.setAllowedAsset(address(0), true);
  }

  function test_SetsAllowedAsset() public {
    // ---- Arrange
    address token = makeAddr("SomeToken");

    // ---- Act
    vm.prank(owner);
    vault.setAllowedAsset(token, true);

    // ---- Assert
    assertTrue(vault.allowedAssets(token));
  }

  function test_EmitsAllowedAssetSetEvent() public {
    // ---- Arrange
    address token = makeAddr("SomeToken");

    vm.expectEmit();
    emit VaultManager.AllowedAssetSet(token, true);

    // ---- Act (event only)
    vm.prank(owner);
    vault.setAllowedAsset(token, true);
  }
}

contract SetAllowedComet is VaultManagerTest {
  function test_RevertIf_CometZeroAddress() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(owner);
    vault.setAllowedComet(address(0), true);
  }

  function test_SetsAllowedComet() public {
    // ---- Arrange
    address c = makeAddr("SomeComet");

    // ---- Act
    vm.prank(owner);
    vault.setAllowedComet(c, true);

    // ---- Assert
    assertTrue(vault.allowedComets(c));
  }

  function test_EmitsAllowedCometSetEvent() public {
    // ---- Arrange
    address c = makeAddr("SomeComet");

    vm.expectEmit();
    emit VaultManager.AllowedCometSet(c, true);

    // ---- Act (event only)
    vm.prank(owner);
    vault.setAllowedComet(c, true);
  }
}

contract SetAssetComet is VaultManagerTest {
  function test_RevertIf_AssetNotAllowListed() public {
    address c = address(comet);
    address newAsset = makeAddr("NewAsset");
    // asset not allowlisted
    vm.expectRevert(VaultManager.VaultManager__AssetNotAllowed.selector);
    vm.prank(owner);
    vault.setAssetComet(newAsset, c);
  }

  function test_RevertIf_CometNotAllowListed() public {
    address notAllowedComet = makeAddr("NotAllowedComet");
    vm.prank(owner);
    vault.setAllowedAsset(address(usdc), true);
    vm.expectRevert(VaultManager.VaultManager__CometNotAllowed.selector);
    vm.prank(owner);
    vault.setAssetComet(address(usdc), notAllowedComet);
  }

  function test_SetsAssetComet() public {
    // ---- Arrange
    address c = address(comet);

    // ---- Act
    vm.prank(owner);
    vault.setAssetComet(address(usdc), c);

    // ---- Assert
    assertEq(vault.assetToComet(address(usdc)), c);
  }

  function test_RevertIf_AssetIsZero() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(owner);
    vault.setAssetComet(address(0), address(comet));
  }

  function test_RevertIf_CometIsZero() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(owner);
    vault.setAssetComet(address(usdc), address(0));
  }

  function test_EmitsAssetCometSetEvent() public {
    // ---- Arrange
    address c = address(comet);

    vm.expectEmit();
    emit VaultManager.AssetCometSet(address(usdc), c);

    // ---- Act (event only)
    vm.prank(owner);
    vault.setAssetComet(address(usdc), c);
  }
}

contract SetAgent is VaultManagerTest {
  function test_RevertIf_NewAgentZero() public {
    vm.expectRevert(VaultManager.VaultManager__InvalidAddress.selector);
    vm.prank(owner);
    vault.setAgent(address(0));
  }

  function test_UpdatesAgentRole() public {
    // ---- Arrange
    address newAgent = makeAddr("NewAgent");

    // ---- Act
    vm.prank(owner);
    vault.setAgent(newAgent);

    // ---- Assert
    assertTrue(vault.hasRole(AGENT_ROLE, newAgent));
  }

  function test_EmitsAgentSetEvent() public {
    // ---- Arrange
    address newAgent = makeAddr("NewAgent");

    vm.expectEmit();
    emit VaultManager.AgentSet(newAgent);

    // ---- Act (event only)
    vm.prank(owner);
    vault.setAgent(newAgent);
  }
}

contract Pause is VaultManagerTest {
  function test_PausesAndBlocksSwap() public {
    // ---- Arrange
    _fundVault(address(usdc), 1e6);
    vm.prank(owner);
    vault.pause();
    assertTrue(vault.paused());

    // ---- Assert
    vm.expectRevert(Pausable.EnforcedPause.selector);

    // ---- Act
    _exactInputSingleAs(owner, address(usdc), address(weth), 1e6);
  }

  function test_UnpausesAndAllowsSwap() public {
    // ---- Arrange
    _fundVault(address(usdc), 1e6);
    vm.startPrank(owner);
    vault.pause();
    vault.unpause();
    vm.stopPrank();
    assertFalse(vault.paused());

    // ---- Act
    _exactInputSingleAs(owner, address(usdc), address(weth), 1e6);

    // ---- Assert
    assertEq(weth.balanceOf(address(vault)), 2e6);
  }
}
