// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Staker, IERC20} from "staker/Staker.sol";
import {StakerPermitAndStake} from "staker/extensions/StakerPermitAndStake.sol";
import {StakerOnBehalf, EIP712} from "staker/extensions/StakerOnBehalf.sol";
import {StakerDelegateSurrogateVotes} from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import {StakerCapDeposits} from "staker/extensions/StakerCapDeposits.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {IEarningPowerCalculator} from "staker/interfaces/IEarningPowerCalculator.sol";

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
  /// @notice Maps a deposit identifier to the validator associated with it.
  /// @dev This mapping is used to track the validator associated with each deposit.
  mapping(Staker.DepositIdentifier depositId => address validator) public validatorForDeposit;

  /// @notice Maps a validator to its stake weight.
  /// @dev This mapping is used to track the stake weight for each validator.
  mapping(address validator => uint256 weight) public validatorStakeWeight;

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
}
