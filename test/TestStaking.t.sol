
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {Staking} from  "../src/Staking.sol";
import {NFT} from  "../src/NFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployStaking} from  "../script/DeployStaking.s.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TestStaking is Test {
    DeployStaking public deployer;
    Staking public staking;
    NFT public nft;
    IERC20 public rewardToken;
    address OWNER = makeAddr("OWNER");
    address USER = makeAddr("USER");
    uint256 rewardAmount = 5000;
    uint256 delayPeriod = 1*60*60; // 1 hour
    uint256 unbondingPeriod = 30*60; // 30 minutes

    event Staked(address indexed user, uint256 tokenId);
    event Claimed(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 tokenId);
    event Withdrawn(address indexed user, uint256 tokenId);

    function setUp() public{
        deployer = new DeployStaking();
        (address nftAddress, address rewardTokenAddress, address stakingAddress) = deployer.run();
        staking = Staking(stakingAddress);
        nft = NFT(nftAddress);
        rewardToken = IERC20(rewardTokenAddress);
    }

    function testStakeShouldFailIfCallerIsNotOwnerOfNFT() public{

        nft.mint(USER, 1);

        vm.expectRevert(Staking.Staking__NotNFTOwner.selector);
        staking.stake(1);
    }

    function testStakeShouldFailIfCallerHasNotApprovedNFT() public{
        nft.mint(USER, 1);

        vm.startPrank(USER);
        vm.expectRevert(Staking.Staking__NotApproved.selector);
        staking.stake(1);
        vm.stopPrank();
    }

    function testUSERShouldBeAbleToStake() public{
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.stopPrank();
        assertEq(staking.getStaker(1), USER);
    }

    function testUSERShouldBeAbleToStakeMultipleNFTs() public{
        nft.mint(USER, 1);
        nft.mint(USER, 2);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        nft.approve(address(staking), 2);
        staking.stake(2);
        vm.stopPrank();
        assertEq(staking.getTotalNftsStaked(USER), 2);
    }

    function testStakeShouldEmitStakedEvent() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Staked(USER, 1);
        staking.stake(1);
        vm.stopPrank();
    }

    function testStakedNFTShouldAccumulateRewards() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.stopPrank();
        vm.roll(block.number + 1);
        assertEq(staking.getRewardsForAddress(USER), rewardAmount);
    }

    function testStakingMultipleNFTsShouldAccumulateRewardsForAllNFTs() public {
        nft.mint(USER, 1);
        nft.mint(USER, 2);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.roll(block.number + 5);
        nft.approve(address(staking), 2);
        staking.stake(2);
        vm.stopPrank();
        vm.roll(block.number + 1);
        assertEq(staking.getRewardsForAddress(USER), rewardAmount * 7); // 6 blocks for 1st NFT and 1 block for 2nd NFT
    }

    function testUserShouldNotBeAbleToClaimRewardsBeforeDelayPeriod() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.warp(block.timestamp + delayPeriod - 1);
        vm.expectRevert(Staking.Staking__CannotClaim.selector);
        staking.claim();
        vm.stopPrank();
    }

    function testUserShouldBeAbleToClaimRewardsAfterDelayPeriod() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.warp(block.timestamp + delayPeriod + 1);
        vm.roll(block.number + 5);
        staking.claim();
        vm.stopPrank();
        assertEq(staking.getRewardsForAddress(USER), 0);
    }

    function testClaimingRewardsShouldEmitClaimedEvent() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.warp(block.timestamp + delayPeriod + 1);
        vm.roll(block.number + 5);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Claimed(USER, rewardAmount*5);
        staking.claim();
        vm.stopPrank();
    }

    function testClaimingRewardsShouldTransferRewardsToUser() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.warp(block.timestamp + delayPeriod + 1);
        vm.roll(block.number + 5);
        staking.claim();
        vm.stopPrank();
        assertEq(rewardToken.balanceOf(USER), rewardAmount*5);
    }

    function testUnstakeShouldFailIfCallerIsNotOwnerOfNFT() public {
        nft.mint(USER, 1);
        vm.expectRevert(Staking.Staking__NotNFTOwner.selector);
        staking.unstake(1);
    }

    function testUserShouldBeAbleToUnstakesNFT() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.stopPrank();
        assertEq(staking.getTotalNftsStaked(USER), 0);
    }

    function testUserShouldBeAbleToUnstakeTheNFTIfItsInUnbondingPeriod() public{
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.warp(block.timestamp + unbondingPeriod -2);
        vm.expectRevert(Staking.Staking__AlreadyUnbonded.selector);
        staking.unstake(1);
        vm.stopPrank();
    }

    function testRewardShouldAcculumateOnlyBeforeUnstaking() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.roll(block.number + 5);
        staking.unstake(1);
        vm.roll(block.number + 1);
        assertEq(staking.getRewardsForAddress(USER), rewardAmount * 5);
    }

    function testclaimRewardShouldRevertIfNoRewards() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.warp(block.timestamp + delayPeriod + 1);
        vm.roll(block.number + 5);
        staking.claim();
        staking.unstake(1);
        vm.warp(block.timestamp + delayPeriod + 1);
        vm.expectRevert(Staking.Staking__CannotClaim.selector);
        staking.claim();
        vm.stopPrank();
    }

    function testUnstakeShouldAbleNumberOfNftStakedByUser() public {
        nft.mint(USER, 1);
        nft.mint(USER, 2);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        nft.approve(address(staking), 2);
        staking.stake(2);
        staking.unstake(1);
        vm.stopPrank();
        assertEq(staking.getTotalNftsStaked(USER), 1);
    }

    function testUnstakeShouldEmitsUnstakedEvent() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Unstaked(USER, 1);
        staking.unstake(1);
        vm.stopPrank();
    }

    function testWithdrawShouldFailIfCallerIsNotOwnerOfNFT() public {
        nft.mint(USER, 1);
        vm.expectRevert(Staking.Staking__NotNFTOwner.selector);
        staking.withdraw(1);
    }

    function testWithdrawShouldRevertIfNFTisNotUnstaked() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.expectRevert(Staking.Staking__NotUnbonded.selector);
        staking.withdraw(1);
        vm.stopPrank();
    }

    function testWithdrawShouldRevertIfNFTisInUnbondingPeriod() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.warp(block.timestamp + unbondingPeriod - 2);
        vm.expectRevert(Staking.Staking__CannotWithdraw.selector);
        staking.withdraw(1);
        vm.stopPrank();
    }

    function testUserShouldBeAbleToWithdrawAfterUnbondingPeriod() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.warp(block.timestamp + unbondingPeriod + 1);
        staking.withdraw(1);
        vm.stopPrank();
        assertEq(staking.getStaker(1), address(0));
    }

    function testWithdrawShouldTransferTheNFTBackToUser() public {
        nft.mint(USER, 1);
        assertEq(nft.ownerOf(1), USER);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.warp(block.timestamp + unbondingPeriod + 1);
        staking.withdraw(1);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), USER);
    }

    function testWithdrawShouldEmitWithdrawnEvent() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        staking.unstake(1);
        vm.warp(block.timestamp + unbondingPeriod + 1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Withdrawn(USER, 1);
        staking.withdraw(1);
        vm.stopPrank();
    }

    function testOwnerShouldBeAbleToPauseStaking() public {
        vm.prank(OWNER);
        staking.pause();
        assertEq(staking.paused(), true);
    }

    function testUSERShouldNtBeAbleToStakeWhenPaused() public {
        nft.mint(USER, 1);
        vm.startPrank(OWNER);
        staking.pause();
        vm.stopPrank();
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        staking.stake(1);
        vm.stopPrank();
    }

    function testOwnerShouldNotBeAbleToCallUnpauseWhenNotPaused() public {
        vm.startPrank(OWNER);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        staking.unpause();
        vm.stopPrank();
    }

    function testOwnerShouldBeAbleToUnpauseTheStakingWhenPaused() public {
        vm.startPrank(OWNER);
        staking.pause();
        assertEq(staking.paused(), true);
        staking.unpause();
        assertEq(staking.paused(), false);
        vm.stopPrank();
    }

    function testOnlyOwnerShouldBeAbleToPauseStaking() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        staking.pause();
    }

    function testOwnerShouldBeAbleToUpdateDelayPeriod() public {
        vm.prank(OWNER);
        staking.setDelayPeriod(2*60*60);
        assertEq(staking.getDelayPeriod(), 2*60*60);
    }

    function testOwnerShouldBeAbleToUpdateUnbondingPeriod() public {
        vm.prank(OWNER);
        staking.setUnbondingPeriod(60*60);
        assertEq(staking.getUnbondingPeriod(), 60*60);
    }

    function testOwnerShouldBeAbleToUpdateRewardAmount() public {
        vm.prank(OWNER);
        staking.setRewardAmount(10000);
        assertEq(staking.getRewardAmount(), 10000);
    }

    function testUSERShouldBeAbleToGetTheirOwnRewards() public {
        nft.mint(USER, 1);
        vm.startPrank(USER);
        nft.approve(address(staking), 1);
        staking.stake(1);
        vm.roll(block.number + 5);
        uint256 totalReward = staking.getRewards();
        vm.stopPrank();
        assertEq(totalReward, rewardAmount*5);
    }

    function testStakingShouldntBeReinitalized() public {
        Staking newStaking = new Staking();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newStaking.initialize(nft, rewardToken, rewardAmount, delayPeriod, unbondingPeriod, OWNER);
    }

    function testStakingCantBeUpdgradedWithZeroAddress() public {
        vm.expectRevert(Staking.Staking__ZeroAddress.selector);
        staking.upgradeToAndCall(address(0), "");
    }

    function testStakingCantBeUpgradedByNonOwner() public {
        Staking newStaking = new Staking();
        vm.prank(USER);
        vm.expectRevert(Staking.Staking__Unauthorized_Upgrade.selector);
        staking.upgradeToAndCall(address(newStaking), "");
    }

    function testStakingCanBeUpgradedByTheOwner() public {
        Staking newStaking = new Staking();
        vm.prank(OWNER);
        staking.upgradeToAndCall(address(newStaking), "");
        assertEq(staking.getImplementation(), address(newStaking));
    }

}