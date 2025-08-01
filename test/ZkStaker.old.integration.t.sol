// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ZkStaker, IERC20} from "src/ZkStaker.sol";
import {PercentAssertions} from "staker-test/helpers/PercentAssertions.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {IdentityEarningPowerCalculator} from "staker/calculators/IdentityEarningPowerCalculator.sol";

contract IntegrationTest is Test {
  address constant ZK_TOKEN_ADDRESS = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  string constant ZKSYNC_RPC_URL = "https://mainnet.era.zksync.io";
  ZkStaker zkStaker;
  IdentityEarningPowerCalculator calculator;
  // ArbitrumDeploy deployScript;
  uint256 constant REWARD_DURATION = 30 days;
  uint256 constant SCALE_FACTOR = 1e36;

  function setUp() public virtual {
    uint256 _forkId = vm.createFork(vm.rpcUrl(ZKSYNC_RPC_URL), 56_644_662);
    vm.selectFork(_forkId);
    calculator = new IdentityEarningPowerCalculator();
    zkStaker = new ZkStaker(
      IERC20(ZK_TOKEN_ADDRESS),
      IERC20Staking(ZK_TOKEN_ADDRESS),
      calculator,
      1e18,
      1e24,
      address(this),
      address(this),
      "ZkStaker",
      1e18,
      true
    );
  }

  function _dealStakingToken(address _recipient, uint96 _amount) internal returns (uint96) {
    // Bound amount to reasonable values
    _amount = uint96(bound(_amount, 0.1e18, 250_000_000e18));
    deal(address(zkStaker.STAKE_TOKEN()), _recipient, _amount);
    return _amount;
  }

  function _jumpAheadByPercentOfRewardDuration(uint256 _percent) internal {
    _percent = bound(_percent, 0, 100);
    vm.warp(block.timestamp + (REWARD_DURATION * _percent) / 100);
  }

  function _boundToRealisticReward(uint256 _rewardAmount) internal pure returns (uint256) {
    // Use much more conservative bounds to prevent overflow
    return bound(_rewardAmount, 1e18, 1_000_000e18); // Max 1M tokens
  }

  function _mintTransferAndNotifyReward(uint256 _rewardAmount) internal {
    // Bound the reward amount to realistic values
    _rewardAmount = _boundToRealisticReward(_rewardAmount);

    // Get the admin from the deployment script
    address admin = zkStaker.admin();
    address rewardNotifier = makeAddr("rewardNotifier");

    // Set up the reward notifier
    vm.prank(admin);
    zkStaker.setRewardNotifier(rewardNotifier, true);

    // Use deal with the bounded amount
    deal(address(zkStaker.REWARD_TOKEN()), rewardNotifier, _rewardAmount);

    // Transfer tokens to the staking contract and notify
    vm.startPrank(rewardNotifier);
    IERC20(address(zkStaker.REWARD_TOKEN())).transfer(address(zkStaker), _rewardAmount);
    zkStaker.notifyRewardAmount(_rewardAmount);
    vm.stopPrank();
  }

  function _boundEligibilityScore(uint256 _score) internal pure returns (uint256) {
    return bound(_score, 50, 100);
  }
}

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
    ZkStaker.DepositIdentifier _depositId =
      zkStaker.stake(_amount, _delegatee, address(0x1), address(0x2));
    vm.stopPrank();

    _mintTransferAndNotifyReward(_rewardAmount);
    _jumpAheadByPercentOfRewardDuration(_percentDuration);

    // Calculate expected rewards based on percentage of duration
    uint256 expectedRewards = (_rewardAmount * _percentDuration) / 100;
    assertLteWithinOnePercent(zkStaker.unclaimedReward(_depositId), expectedRewards);
    // assertEq(zkStaker.);
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

  // TODO: This test is being skipped right now
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
