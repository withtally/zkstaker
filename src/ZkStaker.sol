// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Staker, IERC20} from "staker/Staker.sol";
import {StakerPermitAndStake} from "staker/extensions/StakerPermitAndStake.sol";
import {StakerOnBehalf, EIP712} from "staker/extensions/StakerOnBehalf.sol";
import {StakerDelegateSurrogateVotes} from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import {StakerCapDeposits} from "staker/extensions/StakerCapDeposits.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {IEarningPowerCalculator} from "staker/interfaces/IEarningPowerCalculator.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
  IConsensusRegistryExtended,
  IConsensusRegistry
} from "src/interfaces/IConsensusRegistryExtended.sol";

// these imports needed to get hardhat to include the contracts into the zk-artifacts so the
// deploy script could find them
import {IdentityEarningPowerCalculator} from "staker/calculators/IdentityEarningPowerCalculator.sol";
import {MintRewardNotifier} from "staker/notifiers/MintRewardNotifier.sol";

/// @title ZkStaker
/// @author [ScopeLift](https://scopelift.co)
/// @notice A staking contract for ZK Nation that extends the Staker contract from
/// withtally/staker. This implementation includes permit functionality for gasless approvals,
/// staking on behalf of other addresses, and delegation of voting power through surrogate
/// contracts.
/// @dev This contract combines multiple extension modules from the base Staker.
contract ZkStaker is
  Staker,
  StakerPermitAndStake,
  StakerOnBehalf,
  StakerDelegateSurrogateVotes,
  StakerCapDeposits
{
  using SafeCast for uint256;

  /// @notice Emitted when a validator is altered.
  /// @param depositId The deposit identifier of the altered validator.
  /// @param oldValidator The address of the old validator.
  /// @param newValidator The address of the new validator.
  /// @param earningPower The earning power of the new validator.
  event ValidatorAltered(
    Staker.DepositIdentifier indexed depositId,
    address oldValidator,
    address newValidator,
    uint256 earningPower
  );

  /// @notice Emitted when the validator stake authority is set.
  /// @param oldAuthority The address of the old validator stake authority.
  /// @param newAuthority The address of the new validator stake authority.
  event ValidatorStakeAuthoritySet(address indexed oldAuthority, address indexed newAuthority);

  /// @notice Emitted when the bonus weight of a validator is set.
  /// @param validator The address of the validator.
  /// @param bonusWeight The new bonus weight of the validator.
  event ValidatorBonusWeightSet(address indexed validator, uint256 indexed bonusWeight);

  /// @notice Emitted when the validator weight threshold is set.
  /// @param oldThreshold The previous validator weight threshold.
  /// @param newThreshold The new validator weight threshold.
  event ValidatorWeightThresholdSet(uint256 oldThreshold, uint256 newThreshold);

  /// @notice Emitted when the state of `isLeaderDefault` is changed.
  /// @param oldIsLeaderDefault The previous state of the `isLeaderDefault`.
  /// @param newIsLeaderDefault The new state for the `isLeaderDefault`.
  event IsLeaderDefaultSet(bool oldIsLeaderDefault, bool newIsLeaderDefault);

  /// @notice Emitted when the validator keys are set.
  /// @param validatorOwner The address of the validator owner.
  /// @param newPubKey The new BLS12-381 public key of the validator.
  /// @param newPop The new BLS12-381 signature of the validator.
  event ValidatorKeysSet(
    address indexed validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey newPubKey,
    IConsensusRegistry.BLS12_381Signature newPop
  );

  /// @notice Emitted when the registry is set.
  /// @param oldRegistry The address of the old registry.
  /// @param newRegistry The address of the new registry.
  event RegistrySet(address indexed oldRegistry, address indexed newRegistry);

  /// @notice Emitted when the validator keys are invalid.
  error InvalidValidatorKeys();

  /// @notice Struct to store the validator keys.
  /// @param pubKey The BLS12-381 public key of the validator.
  /// @param pop The BLS12-381 signature of the validator.
  struct ValidatorKeys {
    IConsensusRegistry.BLS12_381PublicKey pubKey;
    IConsensusRegistry.BLS12_381Signature pop;
  }

  /// @notice Maps a deposit identifier to the validator associated with it.
  mapping(Staker.DepositIdentifier depositId => address validator) public validatorForDeposit;

  /// @notice Maps a validator to its stake weight.
  mapping(address validator => uint256 weight) public validatorStakeWeight;

  /// @notice Maps a validator to its bonus weight.
  mapping(address validator => uint256 weight) public validatorBonusWeight;

  /// @notice Maps a validator address to its corresponding BLS12-381 public key and proof of
  /// possession signature.
  mapping(address validator => ValidatorKeys keys) public registeredValidators;

  /// @notice The consensus registry interface used for validator operations.
  IConsensusRegistryExtended public registry;

  /// @notice Address managing validator bonus weights and registry interactions.
  /// @dev The authority can set bonus weights for validators and execute registry operations such
  /// as changing validator leadership and committee settings. It includes pass-through methods for
  /// registry interactions like changing validator leadership, committing the validator committee,
  /// setting committee activation delay, updating leader selection, and changing validator keys.
  address public validatorStakeAuthority;

  /// @notice The minimum weight required for a validator to be considered active in the registry.
  uint256 public validatorWeightThreshold;

  /// @notice The default value for the `isLeader` flag in the registry for actions that require it.
  bool public isLeaderDefault;

  /// @notice Initializes the ZkStaker contract with required parameters.
  /// @param _rewardsToken ERC20 token in which rewards will be denominated.
  /// @param _stakeToken Delegable governance token which users will stake to earn rewards.
  /// @param _earningPowerCalculator The contract that will calculate earning power for stakers.
  /// @param _maxBumpTip Maximum tip that can be paid to bumpers for updating earning power.
  /// @param _initialTotalStakeCap The initial maximum total stake allowed.
  /// @param _admin Address which will have permission to manage reward notifiers.
  /// @param _validatorStakeAuthority Address managing validator bonus weights and registry
  /// interactions.
  /// @param _initialValidatorWeightThreshold The minimum weight required for a validator to be
  /// considered active in the registry.
  /// @param _initialIsLeaderDefault The default value for the `isLeader` flag in the registry for
  /// actions that require it.
  /// @param _name Name used in the EIP712 domain separator for permit functionality.
  constructor(
    IERC20 _rewardsToken,
    IERC20Staking _stakeToken,
    IEarningPowerCalculator _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    address _validatorStakeAuthority,
    string memory _name,
    uint256 _initialValidatorWeightThreshold,
    bool _initialIsLeaderDefault
  )
    Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
    StakerPermitAndStake(_stakeToken)
    StakerDelegateSurrogateVotes(_stakeToken)
    StakerCapDeposits(_initialTotalStakeCap)
    EIP712(_name, "1")
  {
    MAX_CLAIM_FEE = 1e18;
    _setClaimFeeParameters(ClaimFeeParameters({feeAmount: 0, feeCollector: address(0)}));
    _setValidatorStakeAuthority(_validatorStakeAuthority);
    _setValidatorWeightThreshold(_initialValidatorWeightThreshold);
    _setIsLeaderDefault(_initialIsLeaderDefault);
  }

  /// @notice Allows a user to stake a specified amount of tokens, delegate voting power, and
  /// specify a validator.
  /// @param _amount The amount of tokens to stake.
  /// @param _delegatee The address to which voting power is delegated.
  /// @param _claimer The address that can claim rewards on behalf of the staker.
  /// @param _validator The address of the validator associated with the stake.
  /// @return _depositId The identifier of the created deposit.
  function stake(uint256 _amount, address _delegatee, address _claimer, address _validator)
    external
    virtual
    returns (Staker.DepositIdentifier _depositId)
  {
    // TODO: atomically store validator for earning power calculation.

    _depositId = _stake(msg.sender, _amount, _delegatee, _claimer);
    validatorForDeposit[_depositId] = _validator;
    validatorStakeWeight[_validator] += _amount;

    // TODO: Make changes in the registry.
  }

  /// @notice Allows a user to alter the validator associated with a deposit.
  /// @param _depositId The deposit identifier of the deposit to alter.
  /// @param _newValidator The address of the new validator.
  /// @dev Reverts if the deposit is not owned by the caller.
  function alterValidator(Staker.DepositIdentifier _depositId, address _newValidator)
    external
    virtual
  {
    // TODO: atomically store validator for earning power calculation.
    Deposit storage deposit = deposits[_depositId];
    _revertIfNotDepositOwner(deposit, msg.sender);
    _alterValidator(deposit, _depositId, _newValidator);
  }

  /// @notice Sets a new validator stake authority.
  /// @param _newAuthority The address of the new validator stake authority.
  /// @dev This function can only be called by the current admin.
  function setValidatorStakeAuthority(address _newAuthority) external virtual {
    _revertIfNotAdmin();
    _setValidatorStakeAuthority(_newAuthority);
  }

  /// @notice Updates the minimum weight required for a validator to be added to the registry.
  /// @dev This function can only be called by the current admin.
  /// @param _newValidatorWeightThreshold The new weight threshold for validators, which must be met
  /// or exceeded for a validator to be considered active in the registry.
  function setValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) external virtual {
    _revertIfNotAdmin();
    _setValidatorWeightThreshold(_newValidatorWeightThreshold);
  }

  /// @notice Sets the bonus weight for a given validator.
  /// @dev This function can only be called by the validator stake authority.
  /// @param _validator The address of the validator whose bonus weight is being set.
  /// @param _newBonusWeight The new bonus weight to assign to the validator.
  function setBonusWeight(address _validator, uint256 _newBonusWeight) external virtual {
    _revertIfNotValidatorStakeAuthority();
    emit ValidatorBonusWeightSet(_validator, _newBonusWeight);
    validatorBonusWeight[_validator] = _newBonusWeight;
    // TODO: Make changes in the registry.
  }

  /// @notice Sets the consensus registry for the ZkStaker contract.
  /// @dev This function can only be called by the current admin.
  /// @param _registry The new consensus registry to set.
  function setRegistry(IConsensusRegistryExtended _registry) external virtual {
    _revertIfNotAdmin();
    emit RegistrySet(address(registry), address(_registry));
    registry = _registry;
  }

  /// @notice Returns the total weight of a validator, including both stake and bonus weights.
  /// @param _validator The address of the validator to calculate the total weight for.
  /// @return The total weight of the validator, which is the sum of its stake and bonus weights.
  function validatorTotalWeight(address _validator) public view virtual returns (uint256) {
    return (validatorStakeWeight[_validator] + validatorBonusWeight[_validator]);
  }

  /// @notice Sets the default leader status for validators.
  /// @dev This function can only be called by the validator stake authority.
  /// @param _isLeaderDefault The new default leader status to set.
  function setIsLeaderDefault(bool _isLeaderDefault) external virtual {
    _revertIfNotValidatorStakeAuthority();
    _setIsLeaderDefault(_isLeaderDefault);
  }

  /// @notice Registers or changes the validator key for a given validator owner.
  /// @dev This function can be called by the validator owner or the validator stake authority.
  /// It checks for valid BLS12-381 public key and signature before proceeding.
  /// If a registry is set, it updates the registry with the new validator key.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  function registerOrChangeValidatorKey(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) external virtual {
    if (msg.sender != _validatorOwner) _revertIfNotValidatorStakeAuthority();
    if (_isEmptyBLS12_381PublicKey(_validatorPubKey) || _isEmptyBLS12_381Signature(_validatorPoP)) {
      revert InvalidValidatorKeys();
    }

    _setValidatorKeys(_validatorOwner, _validatorPubKey, _validatorPoP);
    if (address(registry) != address(0)) {
      _registerOrChangeValidatorKeyOnTheRegistry(_validatorOwner, _validatorPubKey, _validatorPoP);
    }
  }

  /// @notice Registers existing validators on the registry once a registry contract is set.
  /// @dev This function can be called by the validator owner or the validator stake authority. It
  /// reverts if the provided keys do not match the registered keys for the given validator owner.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  function registerValidatorKeyOnTheRegistry(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public virtual {
    if (msg.sender != _validatorOwner) _revertIfNotValidatorStakeAuthority();
    _revertIfValidatorKeysDoNotMatchRegisteredKeys(_validatorOwner, _validatorPubKey, _validatorPoP);
    _registerOrChangeValidatorKeyOnTheRegistry(_validatorOwner, _validatorPubKey, _validatorPoP);
  }

  /// @notice Reverts if the provided validator keys do not match the registered keys for the given
  /// validator owner.
  /// @param _validatorOwner The address of the validator owner whose keys are being verified.
  /// @param _validatorPubKey The BLS12-381 public key to verify against the registered keys.
  /// @param _validatorPoP The proof-of-possession (PoP) signature to verify against the registered
  /// keys.
  function _revertIfValidatorKeysDoNotMatchRegisteredKeys(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) internal view {
    ValidatorKeys memory registeredKeys = registeredValidators[_validatorOwner];
    if (
      registeredKeys.pubKey.a != _validatorPubKey.a || registeredKeys.pubKey.b != _validatorPubKey.b
        || registeredKeys.pubKey.c != _validatorPubKey.c || registeredKeys.pop.a != _validatorPoP.a
        || registeredKeys.pop.b != _validatorPoP.b
    ) revert InvalidValidatorKeys();
  }

  /// @notice Sets the validator keys for a given validator owner.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  function _setValidatorKeys(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) internal virtual {
    registeredValidators[_validatorOwner] =
      ValidatorKeys({pubKey: _validatorPubKey, pop: _validatorPoP});
    emit ValidatorKeysSet(_validatorOwner, _validatorPubKey, _validatorPoP);
  }

  /// @notice Registers or changes the validator key on the registry.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  function _registerOrChangeValidatorKeyOnTheRegistry(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) internal virtual {
    bool _isInRegistry = _isValidatorRegisteredAndNotRemovedOnTheRegistry(_validatorOwner);
    uint256 _weight = validatorTotalWeight(_validatorOwner);
    bool _isAboveThreshold = _weight >= validatorWeightThreshold;

    if (!_isInRegistry && _isAboveThreshold) {
      registry.add(_validatorOwner, isLeaderDefault, true, _weight, _validatorPubKey, _validatorPoP);
    } else if (_isInRegistry) {
      registry.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);
    }
  }

  /// @notice Checks if a validator is registered and not removed on the registry.
  /// @param _validatorOwner The address of the validator owner.
  /// @return True if the validator is registered and not removed on the registry, false otherwise.
  function _isValidatorRegisteredAndNotRemovedOnTheRegistry(address _validatorOwner)
    internal
    virtual
    returns (bool)
  {
    IConsensusRegistry.Validator memory _validator = registry.validators(_validatorOwner);
    return !_isEmptyBLS12_381PublicKey(_validator.latest.pubKey) && !_validator.latest.removed;
  }

  /// @notice Allows a user to alter the validator associated with a deposit.
  /// @param _depositId The deposit identifier of the deposit to alter.
  /// @param _newValidator The address of the new validator.
  function _alterValidator(
    Deposit storage deposit,
    Staker.DepositIdentifier _depositId,
    address _newValidator
  ) internal virtual {
    _checkpointGlobalReward();
    _checkpointReward(deposit);

    uint256 _newEarningPower =
      earningPowerCalculator.getEarningPower(deposit.balance, deposit.owner, deposit.delegatee);
    totalEarningPower =
      _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
    depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
      deposit.earningPower, _newEarningPower, depositorTotalEarningPower[deposit.owner]
    );
    deposit.earningPower = _newEarningPower.toUint96();

    uint256 _depositBalance = deposit.balance;
    address _oldValidator = validatorForDeposit[_depositId];

    validatorStakeWeight[_oldValidator] -= _depositBalance;
    validatorStakeWeight[_newValidator] += _depositBalance;

    // TODO: Make changes in the registry.

    emit ValidatorAltered(_depositId, _oldValidator, _newValidator, _newEarningPower);
    validatorForDeposit[_depositId] = _newValidator;
  }

  /// @inheritdoc Staker
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stake(address _depositor, uint256 _amount, address _delegatee, address _claimer)
    internal
    virtual
    override(Staker, StakerCapDeposits)
    returns (DepositIdentifier _depositId)
  {
    return StakerCapDeposits._stake(_depositor, _amount, _delegatee, _claimer);
  }

  /// @inheritdoc Staker
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual
    override(Staker, StakerCapDeposits)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    // TODO: atomically store validator for earning power calculation.
    validatorStakeWeight[_depositValidator] += _amount;
    // TODO: Make changes in the registry.

    StakerCapDeposits._stakeMore(deposit, _depositId, _amount);
  }

  /// @notice Internal helper method to set the validator stake authority.
  /// @param _newAuthority The address of the new validator stake authority.
  function _setValidatorStakeAuthority(address _newAuthority) internal virtual {
    emit ValidatorStakeAuthoritySet(validatorStakeAuthority, _newAuthority);
    validatorStakeAuthority = _newAuthority;
  }

  /// @notice Internal function to set the validator weight threshold.
  /// @param _newValidatorWeightThreshold The new threshold value for validator weight.
  function _setValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) internal virtual {
    emit ValidatorWeightThresholdSet(validatorWeightThreshold, _newValidatorWeightThreshold);
    validatorWeightThreshold = _newValidatorWeightThreshold;
  }

  /// @notice Internal function to set the default leader status.
  /// @param _newIsLeaderDefault The new default leader status to be set.
  function _setIsLeaderDefault(bool _newIsLeaderDefault) internal virtual {
    emit IsLeaderDefaultSet(isLeaderDefault, _newIsLeaderDefault);
    isLeaderDefault = _newIsLeaderDefault;
  }

  /// @notice Helper method that reverts if the caller is not the validator stake authority.
  function _revertIfNotValidatorStakeAuthority() internal virtual {
    if (msg.sender != validatorStakeAuthority) {
      revert Staker__Unauthorized("not validator stake authority", msg.sender);
    }
  }

  /// @notice Checks if a validator is registered.
  /// @dev A validator is considered registered if both its BLS12-381 public key and proof of
  /// possession signature are non-empty.
  /// @param _validator The address of the validator to check.
  /// @return True if the validator is registered, false otherwise.
  function _isValidatorRegistered(address _validator) internal virtual returns (bool) {
    ValidatorKeys memory _keys = registeredValidators[_validator];
    return !(_isEmptyBLS12_381PublicKey(_keys.pubKey) && _isEmptyBLS12_381Signature(_keys.pop));
  }

  /// @notice Checks if a BLS12-381 public key is empty.
  /// @param _pubKey The BLS12-381 public key to check.
  /// @return True if the public key is empty, false otherwise.
  function _isEmptyBLS12_381PublicKey(IConsensusRegistry.BLS12_381PublicKey memory _pubKey)
    private
    pure
    returns (bool)
  {
    return _pubKey.a == bytes32(0) && _pubKey.b == bytes32(0) && _pubKey.c == bytes32(0);
  }

  /// @notice Checks if a BLS12-381 signature is empty.
  /// @param _pop The BLS12-381 signature to check.
  /// @return True if the signature is empty, false otherwise.
  function _isEmptyBLS12_381Signature(IConsensusRegistry.BLS12_381Signature memory _pop)
    private
    pure
    returns (bool)
  {
    return _pop.a == bytes32(0) && _pop.b == bytes16(0);
  }
}
