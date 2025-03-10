// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZkStaker, IERC20, IEarningPowerCalculator} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {ERC20Fake} from "staker-test/fakes/ERC20Fake.sol";
import {ERC20VotesMock} from "staker-test/mocks/MockERC20Votes.sol";
import {MockFullEarningPowerCalculator} from "staker-test/mocks/MockFullEarningPowerCalculator.sol";

contract ZkStakerTestBase is Test {
  ERC20Fake rewardToken;
  ERC20VotesMock govToken;
  MockFullEarningPowerCalculator earningPowerCalculator;
  ZkStaker zkStaker;

  address admin;
  uint256 maxBumpTip;
  uint256 initialTotalStakeCap;
  string name;

  function setUp() public virtual {
    rewardToken = new ERC20Fake();
    govToken = new ERC20VotesMock();
    earningPowerCalculator = new MockFullEarningPowerCalculator();
    admin = makeAddr("admin");
    maxBumpTip = 1e18;
    initialTotalStakeCap = 1e24;
    name = "ZkStaker";
  }

  /// @dev Helper function to validate addresses for fuzz tests
  function _validateAddresses(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    address _admin
  ) internal pure {
    // Ensure no zero addresses
    vm.assume(_rewardToken != address(0));
    vm.assume(_stakeToken != address(0));
    vm.assume(_earningPowerCalculator != address(0));
    vm.assume(_admin != address(0));

    // Ensure addresses are different
    vm.assume(_rewardToken != _stakeToken);
    vm.assume(_rewardToken != _earningPowerCalculator);
    vm.assume(_stakeToken != _earningPowerCalculator);
  }
}

contract Constructor is ZkStakerTestBase {
  function test_SetsInitializationParameters() public {
    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      name
    );

    assertEq(address(zkStaker.REWARD_TOKEN()), address(rewardToken));
    assertEq(address(zkStaker.STAKE_TOKEN()), address(govToken));
    assertEq(address(zkStaker.earningPowerCalculator()), address(earningPowerCalculator));
    assertEq(zkStaker.maxBumpTip(), maxBumpTip);
    assertEq(zkStaker.admin(), admin);
  }

  function testFuzz_SetsTheRewardTokenStakeTokenAndOwnerToArbitraryAddresses(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    string memory _name
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    zkStaker = new ZkStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      IEarningPowerCalculator(_earningPowerCalculator),
      _maxBumpTip,
      _initialTotalStakeCap,
      _admin,
      _name
    );

    assertEq(address(zkStaker.REWARD_TOKEN()), _rewardToken);
    assertEq(address(zkStaker.STAKE_TOKEN()), _stakeToken);
    assertEq(address(zkStaker.earningPowerCalculator()), _earningPowerCalculator);
    assertEq(zkStaker.maxBumpTip(), _maxBumpTip);
    assertEq(zkStaker.totalStakeCap(), _initialTotalStakeCap);
    assertEq(zkStaker.admin(), _admin);
  }

  function testFuzz_SetsClaimFeeParameters(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    string memory _name
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    zkStaker = new ZkStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      IEarningPowerCalculator(_earningPowerCalculator),
      _maxBumpTip,
      _initialTotalStakeCap,
      _admin,
      _name
    );

    assertEq(zkStaker.MAX_CLAIM_FEE(), 1e18);
    (uint96 feeAmount, address feeCollector) = zkStaker.claimFeeParameters();
    assertEq(feeAmount, 0);
    assertEq(feeCollector, address(0));
  }
}
