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

  mapping(Staker.DepositIdentifier depositId => address validator) public validatorForDeposit;

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
    string memory _name
  )
    Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
    StakerPermitAndStake(_stakeToken)
    StakerDelegateSurrogateVotes(_stakeToken)
    StakerCapDeposits(_initialTotalStakeCap)
    EIP712(_name, "1")
  {
    MAX_CLAIM_FEE = 1e18;
    _setClaimFeeParameters(ClaimFeeParameters({feeAmount: 0, feeCollector: address(0)}));
  }


  function stake(uint256 _amount, address _delegatee, address _claimer, address _validator)
    external
    virtual
    returns (Staker.DepositIdentifier _depositId)
  {
    validatorForAtomicEarningPowerCalculation = _validator;
    _depositId = _stake(msg.sender, _amount, _delegatee, _claimer);
    validatorForDeposit[_depositId] = _validator;
    validatorForAtomicEarningPowerCalculation = address(0x0);
  }

  function alterValidator(Staker.DepositIdentifier _depositId, address _newValidator) external virtual {
    validatorForAtomicEarningPowerCalculation = _newValidator;
    Deposit storage deposit = deposits[_depositId];
    _revertIfNotDepositOwner(deposit, msg.sender);
    _alterValidator(deposit, _depositId, _newValidator);
    validatorForAtomicEarningPowerCalculation = address(0x0);
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

    emit ValidatorAltered(_depositId, validatorForDeposit[_depositId], _newValidator, _newEarningPower);
    validatorForDeposit[_depositId] = _newValidator;
    deposit.earningPower = _newEarningPower.toUint96();
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

  /// @inheritdoc Staker
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual
    override(Staker, StakerCapDeposits)
  {
    StakerCapDeposits._stakeMore(deposit, _depositId, _amount);
  }
}
