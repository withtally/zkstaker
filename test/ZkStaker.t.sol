// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZkStaker, Staker, IERC20, IEarningPowerCalculator} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {ERC20Fake} from "staker-test/fakes/ERC20Fake.sol";
import {ERC20VotesMock} from "staker-test/mocks/MockERC20Votes.sol";
import {MockFullEarningPowerCalculator} from "staker-test/mocks/MockFullEarningPowerCalculator.sol";
import {IConsensusRegistry} from "src/interfaces/IConsensusRegistry.sol";

contract ZkStakerTestBase is Test {
  ERC20Fake rewardToken;
  ERC20VotesMock govToken;
  MockFullEarningPowerCalculator earningPowerCalculator;
  ZkStaker zkStaker;

  address admin;
  address validatorStakeAuthority;
  uint256 maxBumpTip;
  uint256 initialTotalStakeCap;
  string name;
  uint256 initialValidatorWeightThreshold;
  bool initialIsLeaderDefault;

  function setUp() public virtual {
    rewardToken = new ERC20Fake();
    govToken = new ERC20VotesMock();
    earningPowerCalculator = new MockFullEarningPowerCalculator();
    maxBumpTip = 1e18;
    initialTotalStakeCap = 1e24;
    admin = makeAddr("admin");
    validatorStakeAuthority = makeAddr("validatorStakeAuthority");
    name = "ZkStaker";
    initialValidatorWeightThreshold = 1e18;
    initialIsLeaderDefault = true;

    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      validatorStakeAuthority,
      name,
      initialValidatorWeightThreshold,
      initialIsLeaderDefault
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

  function _fetchDeposit(Staker.DepositIdentifier _depositId)
    internal
    view
    returns (Staker.Deposit memory)
  {
    (
      uint96 _balance,
      address _owner,
      uint96 _earningPower,
      address _delegatee,
      address _claimer,
      uint256 _rewardPerTokenCheckpoint,
      uint256 _scaledUnclaimedRewardCheckpoint
    ) = zkStaker.deposits(_depositId);
    return Staker.Deposit({
      balance: _balance,
      owner: _owner,
      delegatee: _delegatee,
      claimer: _claimer,
      earningPower: _earningPower,
      rewardPerTokenCheckpoint: _rewardPerTokenCheckpoint,
      scaledUnclaimedRewardCheckpoint: _scaledUnclaimedRewardCheckpoint
    });
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
      validatorStakeAuthority,
      name,
      initialValidatorWeightThreshold,
      initialIsLeaderDefault
    );

    assertEq(address(zkStaker.REWARD_TOKEN()), address(rewardToken));
    assertEq(address(zkStaker.STAKE_TOKEN()), address(govToken));
    assertEq(address(zkStaker.earningPowerCalculator()), address(earningPowerCalculator));
    assertEq(zkStaker.maxBumpTip(), maxBumpTip);
    assertEq(zkStaker.admin(), admin);
    assertEq(zkStaker.validatorStakeAuthority(), validatorStakeAuthority);
    assertEq(zkStaker.validatorWeightThreshold(), initialValidatorWeightThreshold);
  }

  function test_EmitsValidatorStakeAuthoritySetEvent() public {
    vm.expectEmit();
    emit ZkStaker.ValidatorStakeAuthoritySet(address(0), validatorStakeAuthority);
    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      validatorStakeAuthority,
      name,
      initialValidatorWeightThreshold,
      initialIsLeaderDefault
    );
  }

  function test_EmitsIsLeaderDefaultSetEvent() public {
    vm.expectEmit();
    emit ZkStaker.IsLeaderDefaultSet(false, initialIsLeaderDefault);
    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      validatorStakeAuthority,
      name,
      initialValidatorWeightThreshold,
      initialIsLeaderDefault
    );
  }

  function test_EmitsValidatorWeightThresholdSetEvent() public {
    vm.expectEmit();
    emit ZkStaker.ValidatorWeightThresholdSet(0, initialValidatorWeightThreshold);
    zkStaker = new ZkStaker(
      IERC20(address(rewardToken)),
      IERC20Staking(address(govToken)),
      IEarningPowerCalculator(address(earningPowerCalculator)),
      maxBumpTip,
      initialTotalStakeCap,
      admin,
      validatorStakeAuthority,
      name,
      initialValidatorWeightThreshold,
      initialIsLeaderDefault
    );
  }

  function testFuzz_SetsTheRewardTokenStakeTokenAndOwnerToArbitraryAddresses(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    address _validatorStakeAuthority,
    string memory _name,
    uint256 _initialValidatorWeightThreshold,
    bool _initialIsLeaderDefault
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    zkStaker = new ZkStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      IEarningPowerCalculator(_earningPowerCalculator),
      _maxBumpTip,
      _initialTotalStakeCap,
      _admin,
      _validatorStakeAuthority,
      _name,
      _initialValidatorWeightThreshold,
      _initialIsLeaderDefault
    );

    assertEq(address(zkStaker.REWARD_TOKEN()), _rewardToken);
    assertEq(address(zkStaker.STAKE_TOKEN()), _stakeToken);
    assertEq(address(zkStaker.earningPowerCalculator()), _earningPowerCalculator);
    assertEq(zkStaker.maxBumpTip(), _maxBumpTip);
    assertEq(zkStaker.totalStakeCap(), _initialTotalStakeCap);
    assertEq(zkStaker.admin(), _admin);
    assertEq(zkStaker.validatorStakeAuthority(), _validatorStakeAuthority);
    assertEq(zkStaker.validatorWeightThreshold(), _initialValidatorWeightThreshold);
  }

  function testFuzz_SetsClaimFeeParameters(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    address _validatorStakeAuthority,
    string memory _name,
    uint256 _initialValidatorWeightThreshold,
    bool _initialIsLeaderDefault
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    zkStaker = new ZkStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      IEarningPowerCalculator(_earningPowerCalculator),
      _maxBumpTip,
      _initialTotalStakeCap,
      _admin,
      _validatorStakeAuthority,
      _name,
      _initialValidatorWeightThreshold,
      _initialIsLeaderDefault
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

contract AlterValidator is ZkStakerTestBase {
  function testFuzz_ChangesTheValidatorOfTheAssociatedDeposit(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.validatorForDeposit(_depositId), _newValidator);
  }

  function testFuzz_ChangesTheStakeWeightOfTheOldAndNewValidator(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    vm.assume(_validator != _newValidator);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    uint256 _previousValidatorStakeWeight = zkStaker.validatorStakeWeight(_validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.validatorStakeWeight(_validator), _previousValidatorStakeWeight - _amount);
    assertEq(zkStaker.validatorStakeWeight(_newValidator), _amount);
  }

  function testFuzz_AllowsTheDepositorToReiterateTheirExistingValidator(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    uint256 _previousValidatorStakeWeight = zkStaker.validatorStakeWeight(_validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _validator);

    assertEq(_previousValidatorStakeWeight, _amount);
    assertEq(zkStaker.validatorStakeWeight(_validator), _amount);
  }

  function testFuzz_EmitsValidatorAlteredEvent(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.expectEmit();
    emit ZkStaker.ValidatorAltered(_depositId, _validator, _newValidator, _amount);
    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);
  }

  function testFuzz_UpdatesDepositEarningPower(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    uint96 _newEarningPower
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    earningPowerCalculator.__setEarningPowerForDelegatee(_delegatee, _newEarningPower);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    Staker.Deposit memory _deposit = _fetchDeposit(_depositId);
    assertEq(_deposit.earningPower, _newEarningPower);
  }

  function testFuzz_UpdatesGlobalTotalEarningPower(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    uint96 _newEarningPower
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    earningPowerCalculator.__setEarningPowerForDelegatee(_delegatee, _newEarningPower);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.totalEarningPower(), _newEarningPower);
  }

  function testFuzz_UpdatesDepositorTotalEarningPower(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    uint96 _newEarningPower
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    earningPowerCalculator.__setEarningPowerForDelegatee(_delegatee, _newEarningPower);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.depositorTotalEarningPower(_depositor), _newEarningPower);
  }

  function testFuzz_RevertIf_NotDepositOwner(
    address _depositor,
    address _notDepositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    vm.assume(_notDepositor != _depositor);
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not owner"), _notDepositor
      )
    );
    vm.prank(_notDepositor);
    zkStaker.alterValidator(_depositId, _newValidator);
  }

  function testFuzz_RevertIf_TheDepositIdentifierIsInvalid(
    address _depositor,
    Staker.DepositIdentifier _invalidDepositId,
    address _newValidator
  ) public {
    vm.assume(_depositor != address(0));

    vm.expectRevert(
      abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not owner"), _depositor)
    );
    vm.prank(_depositor);
    zkStaker.alterValidator(_invalidDepositId, _newValidator);
  }

  function testFuzz_SetsScaledEarningPowerWhenCalculatorScalesStakeAmount(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    uint256 _multiplierBips
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    _multiplierBips = bound(_multiplierBips, 0, 20_000);
    earningPowerCalculator.__setMultiplierBips(_multiplierBips);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    uint256 _expectedEarningPower = (_amount * _multiplierBips) / 10_000;
    Staker.Deposit memory _deposit = _fetchDeposit(_depositId);
    assertEq(_deposit.earningPower, _expectedEarningPower);
    assertEq(zkStaker.totalEarningPower(), _expectedEarningPower);
    assertEq(zkStaker.depositorTotalEarningPower(_depositor), _expectedEarningPower);
  }

  function testFuzz_SetsFixedEarningPowerWhenCalculatorReturnsConstantAmount(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    uint256 _fixedEarningPower
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    _fixedEarningPower = bound(_fixedEarningPower, 0.1e18, 25_000_000e18);

    earningPowerCalculator.__setFixedReturn(_fixedEarningPower);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    Staker.Deposit memory _deposit = _fetchDeposit(_depositId);
    assertEq(_deposit.earningPower, _fixedEarningPower);
    assertEq(zkStaker.totalEarningPower(), _fixedEarningPower);
    assertEq(zkStaker.depositorTotalEarningPower(_depositor), _fixedEarningPower);
  }
}

contract SetValidatorStakeAuthority is ZkStakerTestBase {
  function testFuzz_SetsValidatorStakeAuthority(address _newAuthority) public {
    vm.prank(admin);
    zkStaker.setValidatorStakeAuthority(_newAuthority);
    assertEq(zkStaker.validatorStakeAuthority(), _newAuthority);
  }

  function testFuzz_EmitsValidatorStakeAuthoritySetEvent(address _newAuthority) public {
    vm.expectEmit();
    emit ZkStaker.ValidatorStakeAuthoritySet(validatorStakeAuthority, _newAuthority);
    vm.prank(admin);
    zkStaker.setValidatorStakeAuthority(_newAuthority);
  }

  function testFuzz_RevertIf_NotAdmin(address _caller, address _newAuthority) public {
    vm.assume(_caller != admin);
    vm.expectRevert(
      abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), _caller)
    );
    vm.prank(_caller);
    zkStaker.setValidatorStakeAuthority(_newAuthority);
  }
}

contract SetBonusWeight is ZkStakerTestBase {
  function testFuzz_SetsBonusWeight(address _validator, uint256 _newBonusWeight) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _newBonusWeight);
    assertEq(zkStaker.validatorBonusWeight(_validator), _newBonusWeight);
  }

  function testFuzz_EmitsValidatorBonusWeightSetEvent(address _validator, uint256 _newBonusWeight)
    public
  {
    vm.expectEmit();
    emit ZkStaker.ValidatorBonusWeightSet(_validator, _newBonusWeight);
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _newBonusWeight);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(
    address _caller,
    address _validator,
    uint256 _newBonusWeight
  ) public {
    vm.assume(_caller != validatorStakeAuthority);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    vm.prank(_caller);
    zkStaker.setBonusWeight(_validator, _newBonusWeight);
  }
}

contract SetIsLeaderDefault is ZkStakerTestBase {
  function testFuzz_SetsIsLeaderDefault(bool _isLeaderDefault) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.setIsLeaderDefault(_isLeaderDefault);
    assertEq(zkStaker.isLeaderDefault(), _isLeaderDefault);
  }

  function testFuzz_EmitsIsLeaderDefaultSetEvent(bool _isLeaderDefault) public {
    vm.expectEmit();
    emit ZkStaker.IsLeaderDefaultSet(zkStaker.isLeaderDefault(), _isLeaderDefault);
    vm.prank(validatorStakeAuthority);
    zkStaker.setIsLeaderDefault(_isLeaderDefault);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller, bool _isLeaderDefault)
    public
  {
    vm.assume(_caller != validatorStakeAuthority);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    vm.prank(_caller);
    zkStaker.setIsLeaderDefault(_isLeaderDefault);
  }
}

contract SetValidatorWeightThreshold is ZkStakerTestBase {
  function testFuzz_SetsValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) public {
    vm.prank(admin);
    zkStaker.setValidatorWeightThreshold(_newValidatorWeightThreshold);
    assertEq(zkStaker.validatorWeightThreshold(), _newValidatorWeightThreshold);
  }

  function testFuzz_EmitsValidatorWeightThresholdSetEvent(uint256 _newValidatorWeightThreshold)
    public
  {
    vm.expectEmit();
    emit ZkStaker.ValidatorWeightThresholdSet(
      zkStaker.validatorWeightThreshold(), _newValidatorWeightThreshold
    );
    vm.prank(admin);
    zkStaker.setValidatorWeightThreshold(_newValidatorWeightThreshold);
  }

  function testFuzz_RevertIf_NotAdmin(address _caller, uint256 _newValidatorWeightThreshold) public {
    vm.assume(_caller != admin);
    vm.expectRevert(
      abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), _caller)
    );
    vm.prank(_caller);
    zkStaker.setValidatorWeightThreshold(_newValidatorWeightThreshold);
  }
}

contract ValidatorTotalWeight is ZkStakerTestBase {
  function testFuzz_ReturnsTheSumOfValidatorStakeWeightAndBonusWeight(
    address _depositor,
    address _validator,
    address _delegatee,
    address _claimer,
    uint256 _stakeWeight,
    uint256 _bonusWeight
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    (uint256 boundedStakeWeight,) =
      _boundMintAndStake(_depositor, _stakeWeight, _delegatee, _claimer, _validator);
    _bonusWeight = bound(_bonusWeight, 0, type(uint256).max - boundedStakeWeight);
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _bonusWeight);

    uint256 expectedTotalWeight = boundedStakeWeight + _bonusWeight;
    assertEq(zkStaker.validatorTotalWeight(_validator), expectedTotalWeight);
  }

  function testFuzz_ReturnsCorrectTotalWeightWhenChangingBonusWeightAndAddingStake(
    address _depositor,
    address _validator,
    address _delegatee,
    address _claimer,
    uint256 _initialStakeWeight,
    uint256 _additionalStakeWeight,
    uint256 _initialBonusWeight,
    uint256 _newBonusWeight
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    (uint256 boundedInitialStakeWeight,) =
      _boundMintAndStake(_depositor, _initialStakeWeight, _delegatee, _claimer, _validator);
    _initialBonusWeight =
      bound(_initialBonusWeight, 0, type(uint256).max - boundedInitialStakeWeight);
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _initialBonusWeight);

    (uint256 boundedAdditionalStakeWeight,) =
      _boundMintAndStake(_depositor, _additionalStakeWeight, _delegatee, _claimer, _validator);
    _newBonusWeight = bound(
      _newBonusWeight,
      0,
      type(uint256).max - (boundedInitialStakeWeight + boundedAdditionalStakeWeight)
    );
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _newBonusWeight);

    uint256 expectedTotalWeight =
      boundedInitialStakeWeight + boundedAdditionalStakeWeight + _newBonusWeight;
    assertEq(zkStaker.validatorTotalWeight(_validator), expectedTotalWeight);
  }
}

contract RegisterOrChangeValidatorKey is ZkStakerTestBase {
  function _assumeValidKeys(
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) internal pure {
    vm.assume(
      _validatorPubKey.a != bytes32(0) && _validatorPubKey.b != bytes32(0)
        && _validatorPubKey.c != bytes32(0)
    );
    vm.assume(_validatorPoP.a != bytes32(0) && _validatorPoP.b != bytes16(0));
  }

  function testFuzz_RegisterAsValidator(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.prank(_validator);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);

    zkStaker.registerOrChangeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey.a, _validatorPubKey.a);
    assertEq(_pubKey.b, _validatorPubKey.b);
    assertEq(_pubKey.c, _validatorPubKey.c);
    assertEq(_pop.a, _validatorPoP.a);
    assertEq(_pop.b, _validatorPoP.b);
  }

  function testFuzz_EmitsValidatorKeysSetEvent(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);

    vm.expectEmit();
    emit ZkStaker.ValidatorKeysSet(_validator, _validatorPubKey, _validatorPoP);
    vm.prank(_validator);
    zkStaker.registerOrChangeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }

  function testFuzz_RegistersValidatorAsValidatorStakeAuthority(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validator != validatorStakeAuthority);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.registerOrChangeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey.a, _validatorPubKey.a);
    assertEq(_pubKey.b, _validatorPubKey.b);
    assertEq(_pubKey.c, _validatorPubKey.c);
    assertEq(_pop.a, _validatorPoP.a);
    assertEq(_pop.b, _validatorPoP.b);
  }

  function testFuzz_RevertIf_NotOwnerAndNotValidatorStakeAuthority(
    address _caller,
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_caller != _validator && _caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.registerOrChangeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }

  function testFuzz_RevertIf_InvalidKeys(address _validator) public {
    IConsensusRegistry.BLS12_381PublicKey memory _emptyPubKey =
      IConsensusRegistry.BLS12_381PublicKey({a: bytes32(0), b: bytes32(0), c: bytes32(0)});
    IConsensusRegistry.BLS12_381Signature memory _emptyPoP =
      IConsensusRegistry.BLS12_381Signature({a: bytes32(0), b: bytes16(0)});

    vm.prank(_validator);
    vm.expectRevert(abi.encodeWithSelector(ZkStaker.InvalidValidatorKeys.selector));
    zkStaker.registerOrChangeValidatorKey(_validator, _emptyPubKey, _emptyPoP);
  }
}
