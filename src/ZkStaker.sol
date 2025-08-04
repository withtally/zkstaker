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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

  /// @notice Emitted when the validator weight is updated.
  /// @param validator The address of the validator.
  /// @param newWeight The new weight of the validator.
  event ValidatorTotalWeightUpdated(address indexed validator, uint256 indexed newWeight);

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
  /// @param newPop The new BLS12-381 proof-of-possession signature of the validator.
  event ValidatorKeysSet(
    address indexed validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey newPubKey,
    IConsensusRegistry.BLS12_381Signature newPop
  );

  /// @notice Emitted when the registry is set.
  /// @param oldRegistry The address of the old registry.
  /// @param newRegistry The address of the new registry.
  event RegistrySet(address indexed oldRegistry, address indexed newRegistry);

  /// @notice Thrown when the validator keys are invalid.
  error InvalidValidatorKeys();

  /// @notice Type hash used when encoding data for `stakeOnBehalf` calls.
  bytes32 public constant STAKE_WITH_VALIDATOR_TYPEHASH = keccak256(
    "Stake(uint256 amount,address delegatee,address claimer,address validator,address depositor,uint256 nonce,uint256 deadline)"
  );

  /// @notice Type hash used when encoding data for `alterValidatorOnBehalf` calls.
  bytes32 public constant ALTER_VALIDATOR_TYPEHASH = keccak256(
    "AlterValidator(uint256 depositId,address newValidator,address depositor,uint256 nonce,uint256 deadline)"
  );

  /// @notice Struct to store the validator keys.
  /// @param pubKey The BLS12-381 public key of the validator.
  /// @param pop The BLS12-381 proof-of-possession signature of the validator.
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

  /// @notice Address used for atomic earning power calculation.
  address public validatorForAtomicEarningPowerCalculation;

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
    return _stake(msg.sender, _amount, _delegatee, _claimer, _validator);
  }

  /// @notice Allows a third party to stake tokens on behalf of a depositor.
  /// @param _amount The amount of tokens to stake.
  /// @param _delegatee The address to which voting power is delegated.
  /// @param _claimer The address that can claim rewards on behalf of the staker.
  /// @param _validator The address of the validator associated with the stake.
  /// @param _depositor The address of the depositor on whose behalf the stake is made.
  /// @param _deadline The timestamp by which the transaction must be completed.
  /// @param _signature The signature proving the depositor's consent.
  /// @return _depositId The identifier of the created deposit.
  function stakeOnBehalf(
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator,
    address _depositor,
    uint256 _deadline,
    bytes memory _signature
  ) external virtual returns (DepositIdentifier _depositId) {
    _revertIfPastDeadline(_deadline);
    _revertIfSignatureIsNotValidNow(
      _depositor,
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            STAKE_WITH_VALIDATOR_TYPEHASH,
            _amount,
            _delegatee,
            _claimer,
            _validator,
            _depositor,
            _useNonce(_depositor),
            _deadline
          )
        )
      ),
      _signature
    );
    _depositId = _stake(_depositor, _amount, _delegatee, _claimer, _validator);
  }

  /// @notice Allows a user to alter the validator associated with a deposit.
  /// @param _depositId The deposit identifier of the deposit to alter.
  /// @param _newValidator The address of the new validator.
  /// @dev Reverts if the deposit is not owned by the caller.
  function alterValidator(Staker.DepositIdentifier _depositId, address _newValidator)
    external
    virtual
  {
    validatorForAtomicEarningPowerCalculation = _newValidator;

    Deposit storage deposit = deposits[_depositId];
    _revertIfNotDepositOwner(deposit, msg.sender);
    _alterValidator(deposit, _depositId, _newValidator);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @notice Allows an external party to alter the validator associated with a deposit on behalf of
  /// the depositor.
  /// @param _depositId The identifier of the deposit to alter.
  /// @param _newValidator The address of the new validator to associate with the deposit.
  /// @param _depositor The address of the depositor who owns the deposit.
  /// @param _deadline The timestamp by which the operation must be completed.
  /// @param _signature The signature proving the depositor's consent for the operation.
  function alterValidatorOnBehalf(
    Staker.DepositIdentifier _depositId,
    address _newValidator,
    address _depositor,
    uint256 _deadline,
    bytes memory _signature
  ) external virtual {
    _revertIfPastDeadline(_deadline);
    _revertIfSignatureIsNotValidNow(
      _depositor,
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            ALTER_VALIDATOR_TYPEHASH,
            _depositId,
            _newValidator,
            _depositor,
            _useNonce(_depositor),
            _deadline
          )
        )
      ),
      _signature
    );
    validatorForAtomicEarningPowerCalculation = _newValidator;
    Deposit storage deposit = deposits[_depositId];
    _alterValidator(deposit, _depositId, _newValidator);
    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @notice Sets a new validator stake authority.
  /// @param _newAuthority The address of the new validator stake authority.
  /// @dev This function can only be called by the current admin.
  function setValidatorStakeAuthority(address _newAuthority) external virtual {
    _revertIfNotAdmin();
    _setValidatorStakeAuthority(_newAuthority);
  }

  /// @notice Updates the minimum weight required for a validator to be added to the registry.
  /// @param _newValidatorWeightThreshold The new weight threshold for validators, which must be met
  /// or exceeded for a validator to be considered active in the registry.
  /// @dev This function can only be called by the current admin.
  function setValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) external virtual {
    _revertIfNotAdmin();
    _setValidatorWeightThreshold(_newValidatorWeightThreshold);
  }

  /// @notice Sets the bonus weight for a given validator.
  /// @param _validator The address of the validator whose bonus weight is being set.
  /// @param _newBonusWeight The new bonus weight to assign to the validator.
  /// @dev This function can only be called by the validator stake authority.
  function setBonusWeight(address _validator, uint256 _newBonusWeight) external virtual {
    _revertIfNotValidatorStakeAuthority();
    emit ValidatorBonusWeightSet(_validator, _newBonusWeight);
    validatorBonusWeight[_validator] = _newBonusWeight;
    _changeValidatorWeight(_validator);
  }

  /// @notice Sets the consensus registry for the ZkStaker contract.
  /// @param _registry The new consensus registry to set.
  /// @dev This function can only be called by the current admin.
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
  /// @param _isLeaderDefault The new default leader status to set.
  /// @dev This function can only be called by the validator stake authority.
  function setIsLeaderDefault(bool _isLeaderDefault) external virtual {
    _revertIfNotValidatorStakeAuthority();
    _setIsLeaderDefault(_isLeaderDefault);
  }

  /// @notice Registers or changes the validator key for a given validator owner.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  /// @dev This function can be called by the validator owner or the validator stake authority.
  /// It checks for a valid BLS12-381 public key and signature before proceeding.
  /// If a registry is set, it updates the registry with the new validator key.
  function changeValidatorKey(
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) external virtual {
    if (msg.sender != _validatorOwner) _revertIfNotValidatorStakeAuthority();
    if (_isEmptyBLS12_381PublicKey(_validatorPubKey) || _isEmptyBLS12_381Signature(_validatorPoP)) {
      revert InvalidValidatorKeys();
    }

    _setValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);
    if (address(registry) != address(0)) {
      _setValidatorKeyOnRegistry(_validatorOwner, _validatorPubKey, _validatorPoP);
    }
  }

  /// @notice Changes the leader status of a validator.
  /// @dev This function can only be called by the validator stake authority.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _isLeader The new leader status to set for the validator.
  function changeValidatorLeader(address _validatorOwner, bool _isLeader) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.changeValidatorLeader(_validatorOwner, _isLeader);
  }

  /// @notice Commits the current validator committee.
  /// @dev This function can only be called by the validator stake authority.
  function commitValidatorCommittee() external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.commitValidatorCommittee();
  }

  /// @notice Sets the delay for committee activation.
  /// @dev This function can only be called by the validator stake authority.
  /// @param _delay The new delay in seconds for committee activation.
  function setCommitteeActivationDelay(uint256 _delay) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.setCommitteeActivationDelay(_delay);
  }

  /// @notice Updates the leader selection parameters.
  /// @dev This function can only be called by the validator stake authority.
  /// @param _frequency The frequency of leader selection.
  /// @param _weighted A boolean indicating if the selection should be weighted.
  function updateLeaderSelection(uint64 _frequency, bool _weighted) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.updateLeaderSelection(_frequency, _weighted);
  }

  /// @notice Sets the validator keys for a given validator owner.
  /// @param _validatorOwner The address of the validator owner.
  /// @param _validatorPubKey The BLS12-381 public key of the validator.
  /// @param _validatorPoP The proof-of-possession (PoP) of the validator's public key.
  function _setValidatorKey(
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
  function _setValidatorKeyOnRegistry(
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
    // if not in registry and not above threshold, refrain from registering the validator on the
    // registry
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

    _changeValidatorWeight(_oldValidator);
    _changeValidatorWeight(_newValidator);

    emit ValidatorAltered(_depositId, _oldValidator, _newValidator, _newEarningPower);
    validatorForDeposit[_depositId] = _newValidator;
  }

  /// @inheritdoc Staker
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  /// The validator is assumed to be address(0) when not explicitly specified.
  function _stake(address _depositor, uint256 _amount, address _delegatee, address _claimer)
    internal
    virtual
    override(Staker, StakerCapDeposits)
    returns (DepositIdentifier _depositId)
  {
    return _stake(_depositor, _amount, _delegatee, _claimer, address(0));
  }

  /// @notice Internal function to handle staking with validator specification.
  /// @param _depositor The address of the depositor who is staking tokens.
  /// @param _amount The amount of tokens to be staked.
  /// @param _delegatee The address to which voting power is delegated.
  /// @param _claimer The address that can claim rewards on behalf of the staker.
  /// @param _validator The address of the validator associated with the stake.
  /// @return _depositId The identifier of the created deposit.
  function _stake(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validator
  ) internal virtual returns (DepositIdentifier _depositId) {
    validatorForAtomicEarningPowerCalculation = _validator;

    _depositId = StakerCapDeposits._stake(_depositor, _amount, _delegatee, _claimer);
    validatorForDeposit[_depositId] = _validator;
    validatorStakeWeight[_validator] += _amount;
    _changeValidatorWeight(_validator);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @inheritdoc Staker
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual
    override(Staker, StakerCapDeposits)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    validatorStakeWeight[_depositValidator] += _amount;
    _changeValidatorWeight(_depositValidator);
    StakerCapDeposits._stakeMore(deposit, _depositId, _amount);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @notice Withdraws a specified amount from a deposit.
  /// @param deposit The deposit from which the amount is to be withdrawn.
  /// @param _depositId The identifier of the deposit.
  /// @param _amount The amount to be withdrawn from the deposit.
  /// @dev This function updates the validator's stake weight and adjusts the validator's weight
  /// on the registry. It overrides the _withdraw function from the Staker contract.
  function _withdraw(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual
    override(Staker)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    if (_depositValidator != address(0)) {
      validatorStakeWeight[_depositValidator] -= _amount;
      _changeValidatorWeight(_depositValidator);
    }

    Staker._withdraw(deposit, _depositId, _amount);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @notice Updates the validator's weight on the registry.
  /// @dev This function checks if the validator is registered and updates its weight on the
  /// registry.
  /// If the validator is not in the registry and its weight is above the threshold, it is added.
  /// If the validator is in the registry, its weight is updated, and it is removed if below the
  /// threshold.
  /// @param _validatorOwner The address of the validator owner whose weight is being updated.
  function _changeValidatorWeight(address _validatorOwner) internal virtual {
    uint256 _newWeight = validatorTotalWeight(_validatorOwner);
    emit ValidatorTotalWeightUpdated(_validatorOwner, _newWeight);

    if (!_isValidatorRegistered(_validatorOwner)) return;
    if (address(registry) == address(0)) return;
    ValidatorKeys memory _keys = registeredValidators[_validatorOwner];

    bool _isInRegistry = _isValidatorRegisteredAndNotRemovedOnTheRegistry(_validatorOwner);
    bool _isAboveThreshold = _newWeight >= validatorWeightThreshold;

    if (!_isInRegistry && _isAboveThreshold) {
      registry.add(_validatorOwner, isLeaderDefault, true, _newWeight, _keys.pubKey, _keys.pop);
    }

    if (_isInRegistry) {
      // We don't need to update the weight on the registry if the validator is below the threshold,
      // as it will be removed. When it's re-added, its weight will get overwritten.
      if (!_isAboveThreshold) return registry.remove(_validatorOwner);
      registry.changeValidatorWeight(_validatorOwner, _newWeight);
    }
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

  /// @inheritdoc Staker
  /// @dev We override this function to atomically store the validator for atomic earning power
  /// calculation.
  function _alterClaimer(Deposit storage deposit, DepositIdentifier _depositId, address _newClaimer)
    internal
    virtual
    override(Staker)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    Staker._alterClaimer(deposit, _depositId, _newClaimer);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @inheritdoc Staker
  /// @dev We override this function to atomically store the validator for atomic earning power
  /// calculation.
  function _claimReward(DepositIdentifier _depositId, Deposit storage deposit, address _claimer)
    internal
    virtual
    override(Staker)
    returns (uint256)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    uint256 _payout = Staker._claimReward(_depositId, deposit, _claimer);

    validatorForAtomicEarningPowerCalculation = address(0);

    return _payout;
  }

  /// @inheritdoc Staker
  /// @dev We override this function to atomically store the validator for atomic earning power
  /// calculation.
  function bumpEarningPower(
    DepositIdentifier _depositId,
    address _tipReceiver,
    uint256 _requestedTip
  ) external virtual override(Staker) {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    _bumpEarningPower(_depositId, _tipReceiver, _requestedTip);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  /// @notice Increases the earning power of a deposit.
  /// @dev Validates the requested tip and updates the deposit's earning power and unclaimed
  /// rewards. Same as Staker.bumpEarningPower().
  /// @param _depositId The identifier of the deposit.
  /// @param _tipReceiver The address to receive the tip.
  /// @param _requestedTip The tip amount requested.
  function _bumpEarningPower(
    DepositIdentifier _depositId,
    address _tipReceiver,
    uint256 _requestedTip
  ) internal virtual {
    if (_requestedTip > maxBumpTip) revert Staker__InvalidTip();

    Deposit storage deposit = deposits[_depositId];

    _checkpointGlobalReward();
    _checkpointReward(deposit);

    uint256 _unclaimedRewards = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;

    (uint256 _newEarningPower, bool _isQualifiedForBump) = earningPowerCalculator.getNewEarningPower(
      deposit.balance, deposit.owner, deposit.delegatee, deposit.earningPower
    );
    if (!_isQualifiedForBump || _newEarningPower == deposit.earningPower) {
      revert Staker__Unqualified(_newEarningPower);
    }

    if (_newEarningPower > deposit.earningPower && _unclaimedRewards < _requestedTip) {
      revert Staker__InsufficientUnclaimedRewards();
    }

    // Note: underflow causes a revert if the requested  tip is more than unclaimed rewards
    if (_newEarningPower < deposit.earningPower && (_unclaimedRewards - _requestedTip) < maxBumpTip)
    {
      revert Staker__InsufficientUnclaimedRewards();
    }

    emit EarningPowerBumped(
      _depositId, deposit.earningPower, _newEarningPower, msg.sender, _tipReceiver, _requestedTip
    );

    // Update global earning power & deposit earning power based on this bump
    totalEarningPower =
      _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
    depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
      deposit.earningPower, _newEarningPower, depositorTotalEarningPower[deposit.owner]
    );
    deposit.earningPower = _newEarningPower.toUint96();

    // Send tip to the receiver
    SafeERC20.safeTransfer(REWARD_TOKEN, _tipReceiver, _requestedTip);
    deposit.scaledUnclaimedRewardCheckpoint =
      deposit.scaledUnclaimedRewardCheckpoint - (_requestedTip * SCALE_FACTOR);
  }

  /// @notice Helper method that reverts if the caller is not the validator stake authority.
  function _revertIfNotValidatorStakeAuthority() internal virtual {
    if (msg.sender != validatorStakeAuthority) {
      revert Staker__Unauthorized("not validator stake authority", msg.sender);
    }
  }

  /// @notice Checks if a validator is registered.
  /// @param _validator The address of the validator to check.
  /// @dev A validator is considered registered if both its BLS12-381 public key and proof of
  /// possession signature are non-empty.
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
  /// @param _pop The BLS12-381 proof-of-possession signature to check.
  /// @return True if the signature is empty, false otherwise.
  function _isEmptyBLS12_381Signature(IConsensusRegistry.BLS12_381Signature memory _pop)
    private
    pure
    returns (bool)
  {
    return _pop.a == bytes32(0) && _pop.b == bytes16(0);
  }
}
