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
import {IConsensusRegistry} from "src/IConsensusRegistry.sol";

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

  event ValidatorAltered(
    Staker.DepositIdentifier indexed depositId,
    address oldValidator,
    address newValidator,
    uint256 earningPower
  );

  struct ValidatorKeys {
    IConsensusRegistry.BLS12_381PublicKey pubKey;
    IConsensusRegistry.BLS12_381Signature pop;
  }

  mapping(Staker.DepositIdentifier depositId => address validator) public validatorForDeposit;

  mapping(address validator => uint256 weight) public validatorStakeWeight;

  mapping(address validator => uint256 weight) public validatorBonusWeight;

  address public validatorStakeAuthority;

  uint256 public validatorWeightThreshold;

  bool public isLeaderDefault;

  mapping(address validator => ValidatorKeys keys) registeredValidators;

  // TODO: determine how we will handle the possibility of launching staker when the registry
  // contract has not yet been deployed, but the registry will be added later. Possibilities
  // include making all calls to the registry contingent on 0-address check, or deploying
  // a dummy registry that does nothing. How do either approaches interact with existing state
  // regarding validators that may be on the staker when the real registry is added?
  IConsensusRegistry public registry;

  // TODO: bikeshed the name AND figure out if we can use transient storage for this instead
  address public validatorForAtomicEarningPowerCalculation;

  /// @notice Initializes the ZkStaker contract with required parameters.
  /// @param _rewardsToken ERC20 token in which rewards will be denominated.
  /// @param _stakeToken Delegable governance token which users will stake to earn rewards.
  /// @param _earningPowerCalculator The contract that will calculate earning power for stakers.
  /// @param _maxBumpTip Maximum tip that can be paid to bumpers for updating earning power.
  /// @param _initialTotalStakeCap The initial maximum total stake allowed.
  /// @param _admin Address which will have permission to manage reward notifiers.
  /// @param _name Name used in the EIP712 domain separator for permit functionality.
  constructor(
    IERC20 _rewardsToken,
    IERC20Staking _stakeToken,
    IEarningPowerCalculator _earningPowerCalculator,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    string memory _name,
    address _validatorStakeAuthority,
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

  function validatorTotalWeight(address _validator) public virtual view returns (uint256) {
    return (validatorStakeWeight[_validator] + validatorBonusWeight[_validator]);
  }

  function stake(uint256 _amount, address _delegatee, address _claimer, address _validator)
    external
    virtual
    returns (Staker.DepositIdentifier _depositId)
  {
    validatorForAtomicEarningPowerCalculation = _validator;

    _depositId = _stake(msg.sender, _amount, _delegatee, _claimer);
    validatorForDeposit[_depositId] = _validator;
    validatorStakeWeight[_validator] += _amount;
    // SPIKE TODO: event emission on weight change?

    validatorForAtomicEarningPowerCalculation = address(0x0);
  }

  function alterValidator(Staker.DepositIdentifier _depositId, address _newValidator) external virtual {
    validatorForAtomicEarningPowerCalculation = _newValidator;
    Deposit storage deposit = deposits[_depositId];
    _revertIfNotDepositOwner(deposit, msg.sender);
    _alterValidator(deposit, _depositId, _newValidator);
    validatorForAtomicEarningPowerCalculation = address(0x0);
  }

  function setBonusWeight(address _validator, uint256 _newBonusWeight) external virtual {
    _revertIfNotValidatorStakeAuthority();
    // TODO: Add event emission
    validatorBonusWeight[_validator] = _newBonusWeight;
  }

  function setIsLeaderDefault(bool _newIsLeaderDefault) external virtual {
    _revertIfNotValidatorStakeAuthority();
    _setIsLeaderDefault(_newIsLeaderDefault);
  }

  function setValidatorStakeAuthority(address _newAuthority) external virtual {
    _revertIfNotAdmin();
    _setValidatorStakeAuthority(_newAuthority);
  }

  function setValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) external virtual {
    _revertIfNotAdmin();
    _setValidatorWeightThreshold(_newValidatorWeightThreshold);
  }

  function registerAsValidator(IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey, IConsensusRegistry.BLS12_381Signature calldata _validatorPoP) external virtual {
    ValidatorKeys storage keys = registeredValidators[msg.sender];
    // SPIKE TODO: figure out how to check if the keys are zero
    if (false) {
      // TODO: proper error
      revert();
    }

    uint256 _weight = validatorTotalWeight(msg.sender);

    if (_weight >= validatorWeightThreshold) {
      // SPIKE TODO: figure out how/why weight is represented by a uint32
      registry.add(msg.sender, isLeaderDefault, uint32(_weight), _validatorPubKey, _validatorPoP);
    }
  }

  function _setValidatorWeightThreshold(uint256 _newValidatorWeightThreshold) internal virtual {
    // TODO: Event emission
    validatorWeightThreshold = _newValidatorWeightThreshold;
  }

  function _setValidatorStakeAuthority(address _newAuthority) internal virtual {
    // TODO: Event emission
    validatorStakeAuthority = _newAuthority;
  }

  function _setIsLeaderDefault(bool _newIsLeaderDefault) internal virtual {
    // TODO: Event emission
    isLeaderDefault = _newIsLeaderDefault;
  }

  // PASS THROUGH METHODS
  // --------------------

  function changeValidatorLeader(address _validatorOwner, bool _isLeader) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.changeValidatorLeader(_validatorOwner, _isLeader);
  }

  function commitValidatorCommittee() external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.commitValidatorCommittee();
  }

  function setCommitteeActivationDelay(uint256 _delay) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.setCommitteeActivationDelay(_delay);
  }

  function changeValidatorKey(
        address _validatorOwner,
        IConsensusRegistry.BLS12_381PublicKey calldata _pubKey,
        IConsensusRegistry.BLS12_381Signature calldata _pop
    ) external virtual {
      if (msg.sender != _validatorOwner) {
        _revertIfNotValidatorStakeAuthority();
      }

      registry.changeValidatorKey(_validatorOwner, _pubKey, _pop);
  }

  function updateLeaderSelection(uint64 _frequency, bool _weighted) external virtual {
    _revertIfNotValidatorStakeAuthority();
    registry.updateLeaderSelection(_frequency, _weighted);
  }

  // SPIKE TODO: For every other method where earning power is recalculated, override the method, get
  // the deposit's validator out of storage, put it into the temp variable, call the super method,
  // then clear the temp variable

  function _alterValidator(Deposit storage deposit, Staker.DepositIdentifier _depositId, address _newValidator) internal virtual {
    _checkpointGlobalReward();
    _checkpointReward(deposit);

    uint256 _newEarningPower =
      earningPowerCalculator.getEarningPower(deposit.balance, deposit.owner, deposit.delegatee);

    totalEarningPower =
      _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
    depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
      deposit.earningPower, _newEarningPower, depositorTotalEarningPower[deposit.owner]
    );

    uint256 _depositBalance = deposit.balance;
    address _oldValidator = validatorForDeposit[_depositId];

    validatorStakeWeight[_oldValidator] -= _depositBalance;
    validatorStakeWeight[_newValidator] += _depositBalance;

    emit ValidatorAltered(_depositId, _oldValidator, _newValidator, _newEarningPower);
    validatorForDeposit[_depositId] = _newValidator;
    deposit.earningPower = _newEarningPower.toUint96();
  }

  function _withdraw(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual override(Staker) {
      address _depositValidator = validatorForDeposit[_depositId];
      validatorForAtomicEarningPowerCalculation = _depositValidator;

      validatorStakeWeight[_depositValidator] -= _amount;
      Staker._withdraw(deposit, _depositId, _amount);

      validatorForAtomicEarningPowerCalculation = address(0);
    }

  function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual override(Staker, StakerCapDeposits)
  {
    address _depositValidator = validatorForDeposit[_depositId];
    validatorForAtomicEarningPowerCalculation = _depositValidator;

    validatorStakeWeight[_depositValidator] += _amount;
    StakerCapDeposits._stakeMore(deposit, _depositId, _amount);

    validatorForAtomicEarningPowerCalculation = address(0);
  }

  // TODO: Add signature based onBehalf methods for stake w/ validator & alterValidator

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

  function _revertIfNotValidatorStakeAuthority() internal virtual {
    if (msg.sender != validatorStakeAuthority) {
      // TODO: define a proper error message or use existing authorization error message
      revert();
    }
  }
}
