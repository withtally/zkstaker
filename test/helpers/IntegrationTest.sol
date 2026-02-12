// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ZkStaker, IERC20} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {
 BinaryEligibilityOracleEarningPowerCalculator 
} from "staker/calculators/BinaryEligibilityOracleEarningPowerCalculator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IntegrationTest is Test {
  address constant ZK_TOKEN_ADDRESS = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  string constant ZKSYNC_RPC_URL = "https://mainnet.era.zksync.io";
  ZkStaker zkStaker;
  BinaryEligibilityOracleEarningPowerCalculator calculator;
  // ArbitrumDeploy deployScript;
  uint256 constant REWARD_DURATION = 7 days;
  uint256 constant SCALE_FACTOR = 1e36;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl(ZKSYNC_RPC_URL), 67751772);

    calculator = BinaryEligibilityOracleEarningPowerCalculator(0xe965415bcD29C8B438Ed2012EE92845923E2cd5A);
    ZkStaker implementation = ZkStaker(0x5834E5e4Da8454408DF3e8dd88bd3b164dA736A2);
    ERC1967Proxy proxy = ERC1967Proxy(payable(0x24B5292aDC6CF2373Ddbc09c8699B4F88C6b2CDB));
    zkStaker = ZkStaker(address(proxy));
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

  function _setTotalStakeCap(uint256 _additionalCap) internal {
		  uint256 _totalCap = zkStaker.totalStakeCap();
    vm.prank(0x4eA3EA51f8fDFfb34583C9B729b1c443607Be0bC);
    zkStaker.setTotalStakeCap(_totalCap + _additionalCap);
  }

  function _setDelegateeScore(address _delegatee, uint256 _score) internal {
    vm.prank(calculator.scoreOracle());
    calculator.updateDelegateeScore(_delegatee, _score);
  }

  function _boundEligibilityScore(uint256 _score) internal pure returns (uint256) {
    return bound(_score, 50, 100);
  }
}
