// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ZkStaker, IERC20} from "src/ZkStaker.sol";
import {IntegrationTest} from "test/helpers/IntegrationTest.sol";
import {PercentAssertions} from "staker-test/helpers/PercentAssertions.sol";

/// TODO: Throwing lots of annoying errors
contract Stake is IntegrationTest, PercentAssertions {
  function testForkFuzz_CorrectlyStakeAndEarnRewardsAfterDuration(
    address _depositor,
    uint96 _amount,
    address _delegatee,
    uint256 _rewardAmount,
    uint256 _percentDuration,
    uint256 _eligibilityScore
  ) public {
    vm.assume(_depositor != address(0) && _delegatee != address(0));
    vm.assume(_depositor != address(zkStaker));
    _amount = _dealStakingToken(_depositor, _amount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _amount);
    _rewardAmount = _boundToRealisticReward(_rewardAmount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _eligibilityScore = _boundEligibilityScore(_eligibilityScore);

    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId = zkStaker.stake(_amount, _delegatee);
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    // Calculate expected rewards based on percentage of duration
    uint256 expectedRewards = (_rewardAmount * _percentDuration) / 100;
    assertLteWithinOnePercent(zkStaker.unclaimedReward(_depositId), expectedRewards);
  }

  function testForkFuzz_CorrectlyStakeMoreAndEarnRewardsAfterDuration(
    address _depositor,
    uint96 _initialAmount,
    uint96 _additionalAmount,
    address _delegatee,
    uint256 _rewardAmount,
    uint256 _percentDuration,
    uint256 _eligibilityScore
  ) public {
    vm.assume(_depositor != address(0) && _delegatee != address(0));
    vm.assume(_depositor != address(zkStaker));
    _rewardAmount = _boundToRealisticReward(_rewardAmount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _eligibilityScore = _boundEligibilityScore(_eligibilityScore);

    // Only deal the initial amount first
    _initialAmount = _dealStakingToken(_depositor, _initialAmount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _initialAmount);

    // Approve and stake initial amount
    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _initialAmount);
    ZkStaker.DepositIdentifier _depositId = zkStaker.stake(_initialAmount, _delegatee);
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    // Deal the additional tokens just before staking more
    _additionalAmount = _dealStakingToken(_depositor, _additionalAmount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _additionalAmount);

    // Approve and stake additional amount
    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _additionalAmount);
    zkStaker.stakeMore(_depositId, _additionalAmount);
    vm.stopPrank();

    // Jump ahead to complete the reward duration
    _jumpAheadByPercentOfRewardDuration(100 - _percentDuration);

    // Calculate expected rewards:
    // 1. Rewards earned with initial amount during first period
    uint256 expectedRewardsPeriod1 =
      (_rewardAmount * _percentDuration * _initialAmount) / (100 * (_initialAmount));
    // 2. Rewards earned with combined amount during second period
    uint256 expectedRewardsPeriod2 = (_rewardAmount * (100 - _percentDuration)) / 100;
    uint256 totalExpectedRewards = expectedRewardsPeriod1 + expectedRewardsPeriod2;

    // Assert that the unclaimed rewards are within one percent of the expected amount
    assertLteWithinOnePercent(zkStaker.unclaimedReward(_depositId), totalExpectedRewards);
  }
}

contract Unstake is IntegrationTest, PercentAssertions {
  function testForkFuzz_CorrectlyUnstakeAfterDuration(
    address _depositor,
    uint96 _amount,
    address _delegatee,
    uint256 _rewardAmount,
    uint256 _withdrawAmount,
    uint256 _percentDuration,
    uint256 _eligibilityScore
  ) public {
    vm.assume(_depositor != address(0) && _delegatee != address(0));
    vm.assume(_depositor != address(zkStaker));
    _amount = _dealStakingToken(_depositor, _amount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _amount);
    _rewardAmount = _boundToRealisticReward(_rewardAmount);
    _withdrawAmount = bound(_withdrawAmount, 1e17, _amount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _eligibilityScore = _boundEligibilityScore(_eligibilityScore);

    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId = zkStaker.stake(_amount, _delegatee);
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    uint256 oldBalance = IERC20(address(zkStaker.STAKE_TOKEN())).balanceOf(_depositor);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    uint256 newBalance = IERC20(address(zkStaker.STAKE_TOKEN())).balanceOf(_depositor);
    assertEq(newBalance - oldBalance, _withdrawAmount);
  }
}

contract ClaimRewards is IntegrationTest, PercentAssertions {
  function testForkFuzz_CorrectlyStakeAndClaimRewardsAfterDuration(
    address _depositor,
    uint96 _amount,
    address _delegatee,
    uint256 _rewardAmount,
    uint256 _percentDuration,
    uint256 _eligibilityScore
  ) public {
    vm.assume(_depositor != address(0) && _delegatee != address(0));
    vm.assume(_depositor != address(zkStaker));
    _amount = _dealStakingToken(_depositor, _amount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _amount);
    _rewardAmount = _boundToRealisticReward(_rewardAmount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _eligibilityScore = _boundEligibilityScore(_eligibilityScore);

    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId = zkStaker.stake(_amount, _delegatee);
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    uint256 oldBalance = IERC20(address(zkStaker.REWARD_TOKEN())).balanceOf(_depositor);

    vm.prank(_depositor);
    zkStaker.claimReward(_depositId);

    uint256 newBalance = IERC20(address(zkStaker.REWARD_TOKEN())).balanceOf(_depositor);

    // Calculate expected rewards based on percentage of duration
    uint256 expectedRewards = (_rewardAmount * _percentDuration) / 100;
    assertLteWithinOnePercent(newBalance - oldBalance, expectedRewards);
    assertEq(zkStaker.unclaimedReward(_depositId), 0);
  }

  function testForkFuzz_CorrectlyUnstakeAndClaimRewardsAfterDuration(
    address _depositor,
    uint96 _amount,
    address _delegatee,
    uint256 _rewardAmount,
    uint256 _withdrawAmount,
    uint256 _percentDuration,
    uint256 _eligibilityScore
  ) public {
    vm.skip(true);
    vm.assume(_depositor != address(0) && _delegatee != address(0));
    vm.assume(_depositor != address(zkStaker));
    _amount = _dealStakingToken(_depositor, _amount);
    zkStaker.setTotalStakeCap(zkStaker.totalStakeCap() + _amount);
    _rewardAmount = _boundToRealisticReward(_rewardAmount);
    _withdrawAmount = bound(_withdrawAmount, 1e17, _amount);
    _percentDuration = bound(_percentDuration, 0, 100);
    _eligibilityScore = _boundEligibilityScore(_eligibilityScore);

    vm.startPrank(_depositor);
    IERC20(address(zkStaker.STAKE_TOKEN())).approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId = zkStaker.stake(_amount, _delegatee);
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    uint256 oldStakeBalance = IERC20(address(zkStaker.STAKE_TOKEN())).balanceOf(_depositor);
    uint256 oldRewardBalance = IERC20(address(zkStaker.REWARD_TOKEN())).balanceOf(_depositor);

    vm.startPrank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);
    zkStaker.claimReward(_depositId);
    vm.stopPrank();

    uint256 newStakeBalance = IERC20(address(zkStaker.STAKE_TOKEN())).balanceOf(_depositor);
    uint256 newRewardBalance = IERC20(address(zkStaker.REWARD_TOKEN())).balanceOf(_depositor);

    assertEq(newStakeBalance - oldStakeBalance, _withdrawAmount);

    uint256 expectedRewards = (_rewardAmount * _percentDuration) / 100;
    assertLteWithinOnePercent(newRewardBalance - oldRewardBalance, expectedRewards);
    assertEq(zkStaker.unclaimedReward(_depositId), 0);
  }
}
