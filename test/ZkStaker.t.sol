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
    maxBumpTip = 1e18;
    initialTotalStakeCap = 1e24;
    admin = makeAddr("admin");
    name = "ZkStaker";

    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      name
    );
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

  function _boundAndMintGovToken(address _to, uint256 _amount) internal returns (uint256) {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 0, zkStaker.totalStakeCap() - zkStaker.totalStaked());
    govToken.mint(_to, _amount);
    return _amount;
  }

  function _boundMintAndStake(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) internal returns (uint256 _boundedAmount, ZkStaker.DepositIdentifier _depositId) {
    _boundedAmount = _boundAndMintGovToken(_depositor, _amount);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _boundedAmount);
    _depositId = zkStaker.stake(_boundedAmount, _delegatee, _claimer, _validator);
    vm.stopPrank();
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

contract Stake is ZkStakerTestBase {
  function testFuzz_StakesTokensAndSetsValidatorAndValidatorStakeWeight(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    _amount = _boundAndMintGovToken(_depositor, _amount);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId =
      zkStaker.stake(_amount, _delegatee, _claimer, _validator);
    vm.stopPrank();

    assertEq(zkStaker.validatorForDeposit(_depositId), _validator);
    assertEq(zkStaker.validatorStakeWeight(_validator), _amount);
  }
}

contract StakeMore is ZkStakerTestBase {
  function testFuzz_StakesMoreTokensAndUpdatesValidatorStakeWeight(
    address _depositor,
    uint256 _initialAmount,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_initialAmount, _depositId) =
      _boundMintAndStake(_depositor, _initialAmount, _delegatee, _claimer, _validator);

    _amount = _boundAndMintGovToken(_depositor, _amount);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stakeMore(_depositId, _amount);
    vm.stopPrank();

    assertEq(zkStaker.validatorForDeposit(_depositId), _validator);
    assertEq(zkStaker.validatorStakeWeight(_validator), _initialAmount + _amount);
  }
}
