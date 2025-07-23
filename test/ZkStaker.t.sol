// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {ZkStaker, Staker, IERC20, IEarningPowerCalculator} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {ERC20Fake} from "staker-test/fakes/ERC20Fake.sol";
import {ERC20VotesMock} from "staker-test/mocks/MockERC20Votes.sol";
import {MockFullEarningPowerCalculatorExtended} from
  "test/mocks/MockFullEarningPowerCalculatorExtended.sol";
import {
  IConsensusRegistryExtended,
  IConsensusRegistry
} from "src/interfaces/IConsensusRegistryExtended.sol";
import {ConsensusRegistryMock} from "test/mocks/ConsensusRegistryMock.sol";

contract ZkStakerTestBase is Test {
  ERC20Fake rewardToken;
  ERC20VotesMock govToken;
  MockFullEarningPowerCalculatorExtended earningPowerCalculator;
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
    earningPowerCalculator = new MockFullEarningPowerCalculatorExtended();
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

  function assertEq(
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
    IConsensusRegistry.BLS12_381PublicKey memory _expectedPubKey
  ) internal pure {
    assertEq(_pubKey.a, _expectedPubKey.a);
    assertEq(_pubKey.b, _expectedPubKey.b);
    assertEq(_pubKey.c, _expectedPubKey.c);
  }

  function assertEq(
    IConsensusRegistry.BLS12_381Signature memory _pop,
    IConsensusRegistry.BLS12_381Signature memory _expectedPop
  ) internal pure {
    assertEq(_pop.a, _expectedPop.a);
    assertEq(_pop.b, _expectedPop.b);
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

  function _mintGovToken(address _to, uint256 _amount) internal {
    vm.assume(_to != address(0));
    govToken.mint(_to, _amount);
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

  function _assumeValidDelegateeAndClaimer(address _delegatee, address _claimer) internal pure {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
  }

  function _setMockRegistry() internal {
    ConsensusRegistryMock mockRegistry = new ConsensusRegistryMock();
    vm.prank(admin);
    zkStaker.setRegistry(IConsensusRegistryExtended(address(mockRegistry)));
  }

  function _registerValidator(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) internal {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    vm.prank(_validator);
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }

  function _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    uint256 _bonusWeightAboveThreshold
  ) internal returns (uint256 boundedBonusWeightAboveThreshold) {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    boundedBonusWeightAboveThreshold =
      _boundAndSetBonusWeightAboveThreshold(_validator, _bonusWeightAboveThreshold);
    _setMockRegistry();
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
  }

  function _boundAndSetBonusWeightAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold
  ) internal returns (uint256) {
    _bonusWeightAboveThreshold = bound(
      _bonusWeightAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validatorOwner, _bonusWeightAboveThreshold);
    return _bonusWeightAboveThreshold;
  }

  function _boundAndSetBonusWeightBelowThreshold(
    address _validatorOwner,
    uint256 _bonusWeightBelowThreshold
  ) internal returns (uint256) {
    _bonusWeightBelowThreshold =
      bound(_bonusWeightBelowThreshold, 0, initialValidatorWeightThreshold - 1);
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validatorOwner, _bonusWeightBelowThreshold);
    return _bonusWeightBelowThreshold;
  }

  /// @notice Checks if a BLS12-381 public key is empty.
  /// @param _pubKey The BLS12-381 public key to check.
  /// @return True if the public key is empty, false otherwise.
  function _isEmptyBLS12_381PublicKey(IConsensusRegistry.BLS12_381PublicKey memory _pubKey)
    internal
    pure
    returns (bool)
  {
    return _pubKey.a == bytes32(0) && _pubKey.b == bytes32(0) && _pubKey.c == bytes32(0);
  }

  /// @notice Checks if a BLS12-381 signature is empty.
  /// @param _pop The BLS12-381 proof-of-possession signature to check.
  /// @return True if the signature is empty, false otherwise.
  function _isEmptyBLS12_381Signature(IConsensusRegistry.BLS12_381Signature memory _pop)
    internal
    pure
    returns (bool)
  {
    return _pop.a == bytes32(0) && _pop.b == bytes16(0);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

    _amount = _boundAndMintGovToken(_depositor, _amount);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    ZkStaker.DepositIdentifier _depositId =
      zkStaker.stake(_amount, _delegatee, _claimer, _validator);
    vm.stopPrank();

    assertEq(zkStaker.validatorForDeposit(_depositId), _validator);
    assertEq(zkStaker.validatorStakeWeight(_validator), _amount);
  }

  function testFuzz_EmitsValidatorTotalWeightUpdatedEvent(
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
    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_validator, _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validator);
    vm.stopPrank();
  }

  function testFuzz_AddsValidatorToRegistryWhenValidatorWeightIsAboveThreshold(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _amount);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey.a, _validatorPubKey.a);
    assertEq(_pubKey.b, _validatorPubKey.b);
    assertEq(_pubKey.c, _validatorPubKey.c);
    assertEq(_pop.a, _validatorPoP.a);
    assertEq(_pop.b, _validatorPoP.b);
  }

  function testFuzz_UpdatesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
    address _depositor,
    uint256 _bonusWeightAboveThreshold,
    uint256 _bonusWeightBelowThreshold,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _amount);
    _bonusWeightAboveThreshold = _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _validatorOwner, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );
    _bonusWeightBelowThreshold =
      _boundAndSetBonusWeightBelowThreshold(_validatorOwner, _bonusWeightBelowThreshold);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _bonusWeightBelowThreshold + _amount);
  }

  function testFuzz_ValidatorForAtomicEarningPowerCalculationIsSet(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    _amount = _boundAndMintGovToken(_depositor, _amount);
    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _validator
    );

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validator);
    vm.stopPrank();
  }

  function testFuzz_DoesNotAddValidatorToRegistryWhenValidatorWeightIsBelowThreshold(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _amount = bound(_amount, 0, initialValidatorWeightThreshold - 1);
    _mintGovToken(_depositor, _amount);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_isEmptyBLS12_381PublicKey(_validator.latest.pubKey), true);
    assertEq(_isEmptyBLS12_381Signature(_validator.latest.proofOfPossession), true);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

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

  function testFuzz_EmitsValidatorTotalWeightUpdatedEvent(
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
    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_validator, _initialAmount + _amount);
    zkStaker.stakeMore(_depositId, _amount);
    vm.stopPrank();
  }

  function testFuzz_AddsValidatorToRegistryWhenValidatorWeightIsAboveThreshold(
    address _depositor,
    uint256 _amount,
    uint256 _stakeMoreAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _amount = _boundAndMintGovToken(_depositor, _amount);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    ZkStaker.DepositIdentifier _depositId;
    _amount = bound(_amount, 0, initialValidatorWeightThreshold - 1);
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validatorOwner);

    _stakeMoreAmountAboveThreshold = bound(
      _stakeMoreAmountAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _stakeMoreAmountAboveThreshold);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _stakeMoreAmountAboveThreshold);
    zkStaker.stakeMore(_depositId, _stakeMoreAmountAboveThreshold);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey.a, _validatorPubKey.a);
    assertEq(_pubKey.b, _validatorPubKey.b);
    assertEq(_pubKey.c, _validatorPubKey.c);
    assertEq(_pop.a, _validatorPoP.a);
    assertEq(_pop.b, _validatorPoP.b);
    assertEq(_validator.latest.weight, _amount + _stakeMoreAmountAboveThreshold);
  }

  function testFuzz_UpdatesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
    address _depositor,
    uint256 _amount,
    uint256 _stakeMoreAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _stakeMoreAmountAboveThreshold = bound(
      _stakeMoreAmountAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    ZkStaker.DepositIdentifier _depositId;
    (_stakeMoreAmountAboveThreshold, _depositId) = _boundMintAndStake(
      _depositor, _stakeMoreAmountAboveThreshold, _delegatee, _claimer, _validatorOwner
    );

    _amount = _boundAndMintGovToken(_depositor, _amount);
    _mintGovToken(_depositor, _amount);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stakeMore(_depositId, _amount);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _stakeMoreAmountAboveThreshold + _amount);
  }

  function testFuzz_DoesNotAddValidatorToRegistryWhenValidatorWeightIsBelowThreshold(
    address _depositor,
    uint256 _amount,
    uint256 _stakeMoreAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _amount = _boundAndMintGovToken(_depositor, _amount);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    ZkStaker.DepositIdentifier _depositId;
    _amount = bound(_amount, 0, initialValidatorWeightThreshold - 1);
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validatorOwner);

    _stakeMoreAmountAboveThreshold =
      bound(_stakeMoreAmountAboveThreshold, 0, initialValidatorWeightThreshold - _amount - 1);
    _mintGovToken(_depositor, _stakeMoreAmountAboveThreshold);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _stakeMoreAmountAboveThreshold);
    zkStaker.stakeMore(_depositId, _stakeMoreAmountAboveThreshold);
    vm.stopPrank();

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_isEmptyBLS12_381PublicKey(_pubKey), true);
    assertEq(_isEmptyBLS12_381Signature(_pop), true);
  }

  function testFuzz_ValidatorForAtomicEarningPowerCalculationIsSet(
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

    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _validator
    );

    _amount = _boundAndMintGovToken(_depositor, _amount);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stakeMore(_depositId, _amount);
    vm.stopPrank();
  }
}

contract Withdraw is ZkStakerTestBase {
  function testFuzz_DecreasesValidatorStakeWeight(
    address _depositor,
    uint256 _amount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    _withdrawAmount = bound(_withdrawAmount, 0, _amount);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    assertEq(zkStaker.validatorStakeWeight(_validator), _amount - _withdrawAmount);
  }

  function testFuzz_EmitsValidatorTotalWeightUpdatedEvent(
    address _depositor,
    uint256 _amount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    _withdrawAmount = bound(_withdrawAmount, 0, _amount);

    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_validator, _amount - _withdrawAmount);
    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);
  }

  function testFuzz_UpdatesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
    address _depositor,
    uint256 _stakeAmount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validatorOwner != address(0));
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _stakeAmount = bound(
      _stakeAmount,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (_stakeAmount, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmount, _delegatee, _claimer, _validatorOwner);
    _withdrawAmount = bound(_withdrawAmount, 0, _stakeAmount);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _stakeAmount - _withdrawAmount);
  }

  function testFuzz_RemovesValidatorFromRegistryWhenValidatorIsAlreadyRegisteredButBelowThreshold(
    address _depositor,
    uint256 _stakeAmount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validatorOwner != address(0));
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _stakeAmount = bound(
      _stakeAmount,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (_stakeAmount, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmount, _delegatee, _claimer, _validatorOwner);
    _withdrawAmount =
      bound(_withdrawAmount, _stakeAmount - initialValidatorWeightThreshold + 1, _stakeAmount);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.removed, true);
  }

  function testFuzz_ValidatorForAtomicEarningPowerCalculationIsSet(
    address _depositor,
    uint256 _amount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    vm.assume(_validator != address(0));

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    _withdrawAmount = bound(_withdrawAmount, 0, _amount);

    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _validator
    );

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.validatorForDeposit(_depositId), _newValidator);
  }

  function testFuzz_EmitsValidatorAlteredEvent(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
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

  function testFuzz_EmitsValidatorTotalWeightUpdatedEvent(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    uint256 _previousValidatorStakeWeight = zkStaker.validatorStakeWeight(_validator);

    vm.prank(_depositor);
    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_validator, _previousValidatorStakeWeight - _amount);
    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_newValidator, _amount);
    zkStaker.alterValidator(_depositId, _newValidator);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    uint256 _previousValidatorStakeWeight = zkStaker.validatorStakeWeight(_validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _validator);

    assertEq(_previousValidatorStakeWeight, _amount);
    assertEq(zkStaker.validatorStakeWeight(_validator), _amount);
  }

  function testFuzz_AddsValidatorToRegistryWhenValidatorIsNotRegisteredAndAboveThreshold(
    address _depositor,
    uint256 _stakeAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setMockRegistry();
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _stakeAmountAboveThreshold = bound(
      _stakeAmountAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmountAboveThreshold, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _validator);

    IConsensusRegistry.Validator memory _currentValidator =
      zkStaker.registry().validators(_validator);
    assertEq(_currentValidator.latest.weight, _stakeAmountAboveThreshold);
  }

  function testFuzz_ChangesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
    address _depositor,
    uint256 _amount,
    uint256 _bonusWeightAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != _newValidator);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _setMockRegistry();
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold = _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _newValidator, _newValidatorPubKey, _newValidatorPoP, _bonusWeightAboveThreshold
    );
    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    IConsensusRegistry.Validator memory _previousValidator =
      zkStaker.registry().validators(_validator);
    IConsensusRegistry.Validator memory _currentValidator =
      zkStaker.registry().validators(_newValidator);
    assertEq(_previousValidator.latest.weight, 0);
    assertEq(_currentValidator.latest.weight, _amount + _bonusWeightAboveThreshold);
  }

  function testFuzz_RemovesValidatorFromRegistryWhenValidatorRegisteredButBelowThreshold(
    address _depositor,
    uint256 _amount,
    uint256 _bonusWeightAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != _newValidator);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _setMockRegistry();
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold = _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _newValidator, _newValidatorPubKey, _newValidatorPoP, _bonusWeightAboveThreshold
    );
    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    IConsensusRegistry.Validator memory _previousValidator =
      zkStaker.registry().validators(_validator);
    assertEq(_previousValidator.latest.removed, true);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);
    earningPowerCalculator.__setEarningPowerForDelegatee(_delegatee, _newEarningPower);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    assertEq(zkStaker.depositorTotalEarningPower(_depositor), _newEarningPower);
  }

  function testFuzz_ValidatorForAtomicEarningPowerCalculationIsSet(
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

    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _newValidator
    );

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);

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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
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

contract AlterClaimer is ZkStakerTestBase {
  function testFuzz_SetsValidatorForAtomicEarningPowerCalculation(
    address _depositor,
    uint256 _depositAmount,
    address _delegatee,
    address _firstClaimer,
    address _newClaimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_firstClaimer != address(0));
    vm.assume(_newClaimer != address(0) && _newClaimer != _firstClaimer);

    Staker.DepositIdentifier _depositId;
    (_depositAmount, _depositId) =
      _boundMintAndStake(_depositor, _depositAmount, _delegatee, _firstClaimer, _validator);
    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _validator
    );

    vm.prank(_depositor);
    zkStaker.alterClaimer(_depositId, _newClaimer);
  }
}

contract ClaimReward is ZkStakerTestBase {
  function testFuzz_DepositorReceivesRewardsWhenClaiming(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));

    Staker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    earningPowerCalculator.__setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
      zkStaker, _validator
    );

    vm.prank(_depositor);
    zkStaker.claimReward(_depositId);
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

  function testFuzz_EmitsValidatorTotalWeightUpdatedEvent(
    address _validator,
    uint256 _newBonusWeight
  ) public {
    vm.expectEmit();
    emit ZkStaker.ValidatorTotalWeightUpdated(_validator, _newBonusWeight);
    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validator, _newBonusWeight);
  }

  function testFuzz_AddsValidatorToRegistryWhenBonusWeightIsAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold =
      _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _bonusWeightAboveThreshold);
  }

  function testFuzz_ChangesValidatorWeightOnRegistryWhenItIsAlreadyRegistered(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    uint256 _newBonusWeight,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _validatorOwner, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );

    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validatorOwner, _newBonusWeight);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _newBonusWeight);
  }

  function testFuzz_RemovesValidatorFromRegistryWhenBonusWeightIsBelowThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    uint256 _bonusWeightBelowThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _validatorOwner, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );
    _boundAndSetBonusWeightBelowThreshold(_validatorOwner, _bonusWeightBelowThreshold);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.removed, true);
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
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
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
      bound(_initialBonusWeight, 0, type(uint248).max - boundedInitialStakeWeight);
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

contract SetRegistry is ZkStakerTestBase {
  function testFuzz_AdminSetsRegistry(IConsensusRegistryExtended _newRegistry) public {
    vm.prank(admin);
    zkStaker.setRegistry(_newRegistry);
    assertEq(address(zkStaker.registry()), address(_newRegistry));
  }

  function testFuzz_EmitsRegistrySetEvent(IConsensusRegistryExtended _newRegistry) public {
    vm.expectEmit();
    emit ZkStaker.RegistrySet(address(zkStaker.registry()), address(_newRegistry));
    vm.prank(admin);
    zkStaker.setRegistry(_newRegistry);
  }

  function testFuzz_RevertIf_NotAdmin(address _caller, IConsensusRegistryExtended _newRegistry)
    public
  {
    vm.assume(_caller != admin);
    vm.expectRevert(
      abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), _caller)
    );
    vm.prank(_caller);
    zkStaker.setRegistry(_newRegistry);
  }
}

contract ChangeValidatorKey is ZkStakerTestBase {
  function testFuzz_RegistersValidatorAsOwner(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.prank(_validator);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);

    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey, _validatorPubKey);
    assertEq(_pop, _validatorPoP);
  }

  function testFuzz_RegistersValidatorAsStakeAuthority(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validator != validatorStakeAuthority);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey, _validatorPubKey);
    assertEq(_pop, _validatorPoP);
  }

  function testFuzz_RegistersValidatorAsOwnerOnTheRegistryWhenAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey, _validatorPubKey);
    assertEq(_pop, _validatorPoP);
  }

  function testFuzz_RegistersValidatorAsValidatorStakeAuthorityOnTheRegistryWhenAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);
    _setMockRegistry();
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey, _validatorPubKey);
    assertEq(_pop, _validatorPoP);
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
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsOwner(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validator);
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    vm.prank(_validator);
    zkStaker.changeValidatorKey(_validator, _newValidatorPubKey, _newValidatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey, _newValidatorPubKey);
    assertEq(_pop, _newValidatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsOwnerOnTheRegistryWhenAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);
    _setMockRegistry();

    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _newValidatorPubKey, _newValidatorPoP);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey, _newValidatorPubKey);
    assertEq(_pop, _newValidatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsStakeAuthority(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validator);
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validator, _newValidatorPubKey, _newValidatorPoP);

    (
      IConsensusRegistry.BLS12_381PublicKey memory _pubKey,
      IConsensusRegistry.BLS12_381Signature memory _pop
    ) = zkStaker.registeredValidators(_validator);
    assertEq(_pubKey, _newValidatorPubKey);
    assertEq(_pop, _newValidatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsStakeAuthorityOnTheRegistryWhenAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _bonusWeightAboveThreshold =
      bound(_bonusWeightAboveThreshold, initialValidatorWeightThreshold, type(uint256).max);

    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validatorOwner, _bonusWeightAboveThreshold);
    _setMockRegistry();

    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validatorOwner, _newValidatorPubKey, _newValidatorPoP);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.latest.proofOfPossession;
    assertEq(_pubKey, _newValidatorPubKey);
    assertEq(_pop, _newValidatorPoP);
  }

  function testFuzz_RemovesValidatorFromRegistryWhenValidatorIsAlreadyRegisteredButBelowThreshold(
    uint256 _bonusWeightAboveThreshold,
    uint256 _bonusWeightBelowThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_delegatee != address(0));
    vm.assume(_claimer != address(0));
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _setRegistryAndRegisterValidatorWithBonusWeightAboveThreshold(
      _validatorOwner, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );
    _bonusWeightBelowThreshold =
      _boundAndSetBonusWeightBelowThreshold(_validatorOwner, _bonusWeightBelowThreshold);

    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    IConsensusRegistry.Validator memory _validator = zkStaker.registry().validators(_validatorOwner);
    assertEq(_validator.latest.weight, _bonusWeightBelowThreshold);
    assertEq(_validator.latest.removed, true);
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
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }

  function testFuzz_RevertIf_InvalidKeys(
    uint256 _arbitraryNumber,
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey memory _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature memory _validatorPoP
  ) public {
    if (_arbitraryNumber % 2 == 0) {
      _validatorPubKey =
        IConsensusRegistry.BLS12_381PublicKey({a: bytes32(0), b: bytes32(0), c: bytes32(0)});
    } else {
      _validatorPoP = IConsensusRegistry.BLS12_381Signature({a: bytes32(0), b: bytes16(0)});
    }

    vm.prank(_validator);
    vm.expectRevert(abi.encodeWithSelector(ZkStaker.InvalidValidatorKeys.selector));
    zkStaker.changeValidatorKey(_validator, _validatorPubKey, _validatorPoP);
  }
}

contract ChangeValidatorLeader is ZkStakerTestBase {
  function setUp() public override {
    super.setUp();
    _setMockRegistry();
  }

  function testFuzz_ChangesValidatorLeader(address _validator) public {
    vm.assume(_validator != address(this));
    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorLeader(_validator, true);

    assertEq(zkStaker.registry().validators(_validator).latest.leader, true);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller, address _validator) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.changeValidatorLeader(_validator, true);
  }
}

contract CommitValidatorCommittee is ZkStakerTestBase {
  function setUp() public override {
    super.setUp();
    _setMockRegistry();
  }

  function testFuzz_CommitsValidatorCommittee() public {
    vm.prank(validatorStakeAuthority);
    zkStaker.commitValidatorCommittee();

    uint64 _validatorCommit = zkStaker.registry().validatorsCommit();
    assertEq(_validatorCommit, 1);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.commitValidatorCommittee();
  }
}

contract SetCommitteeActivationDelay is ZkStakerTestBase {
  function setUp() public override {
    super.setUp();
    _setMockRegistry();
  }

  function testFuzz_SetsCommitteeActivationDelay(uint256 _delay) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.setCommitteeActivationDelay(_delay);

    assertEq(zkStaker.registry().committeeActivationDelay(), _delay);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller, uint256 _delay) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.setCommitteeActivationDelay(_delay);
  }
}

contract UpdateLeaderSelection is ZkStakerTestBase {
  function setUp() public override {
    super.setUp();
    _setMockRegistry();
  }

  function testFuzz_UpdatesLeaderSelection(uint64 _frequency, bool _weighted) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.updateLeaderSelection(_frequency, _weighted);

    assertEq(zkStaker.registry().leaderSelection().latest.frequency, _frequency);
    assertEq(zkStaker.registry().leaderSelection().latest.weighted, _weighted);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(
    address _caller,
    uint64 _frequency,
    bool _weighted
  ) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.updateLeaderSelection(_frequency, _weighted);
  }
}
