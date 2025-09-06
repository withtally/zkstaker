// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {StakerUpgradeable, IERC20} from "staker/StakerUpgradeable.sol";
import {StakerPermitAndStakeUpgradeable} from
  "staker/extensions/StakerPermitAndStakeUpgradeable.sol";
import {StakerOnBehalfUpgradeable} from "staker/extensions/StakerOnBehalfUpgradeable.sol";
import {StakerDelegateSurrogateVotesUpgradeable} from
  "staker/extensions/StakerDelegateSurrogateVotesUpgradeable.sol";
import {StakerCapDepositsUpgradeable} from "staker/extensions/StakerCapDepositsUpgradeable.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {IERC20Delegates} from "staker/interfaces/IERC20Delegates.sol";
import {IEarningPowerCalculator} from "staker/interfaces/IEarningPowerCalculator.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

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
  StakerUpgradeable,
  StakerPermitAndStakeUpgradeable,
  StakerOnBehalfUpgradeable,
  StakerDelegateSurrogateVotesUpgradeable,
  StakerCapDepositsUpgradeable
{
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the ZkStaker contract with required parameters.
  /// @param _rewardToken ERC20 token in which rewards will be denominated.
  /// @param _stakeToken Delegable governance token which users will stake to earn rewards.
  /// @param _maxClaimFee The maximum fee to charge when claiming.
  /// @param _admin Address which will have permission to manage reward notifiers.
  /// @param _maxBumpTip Maximum tip that can be paid to bumpers for updating earning power.
  /// @param _earningPowerCalculator The contract that will calculate earning power for stakers.
  /// @param _name Name used in the EIP712 domain separator for permit functionality.
  /// @param _initialStakeCap The initial maximum total stake allowed.
  function initialize(
    IERC20 _rewardToken,
    IERC20 _stakeToken,
    uint256 _maxClaimFee,
    address _admin,
    uint256 _maxBumpTip,
    IEarningPowerCalculator _earningPowerCalculator,
    string memory _name,
    uint256 _initialStakeCap
  ) public initializer {
    __StakerUpgradeable_init(
      _rewardToken, _stakeToken, _maxClaimFee, _admin, _maxBumpTip, _earningPowerCalculator
    );
    __StakerPermitAndStakeUpgradeable_init(IERC20Permit(address(_stakeToken)));
    __StakerDelegateSurrogateVotesUpgradeable_init(IERC20Delegates(address(_stakeToken)));
    __EIP712_init(_name, "1");
    __StakerCapDepositsUpgradeable_init(_initialStakeCap);
    __Nonces_init();
    _setMaxClaimFee(_maxClaimFee);
    _setClaimFeeParameters(ClaimFeeParameters({feeAmount: 0, feeCollector: address(0)}));
  }

  /// @inheritdoc StakerUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stake(address _depositor, uint256 _amount, address _delegatee, address _claimer)
    internal
    virtual
    override(StakerUpgradeable, StakerCapDepositsUpgradeable)
    returns (DepositIdentifier _depositId)
  {
    return StakerCapDepositsUpgradeable._stake(_depositor, _amount, _delegatee, _claimer);
  }

  /// @inheritdoc StakerUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount)
    internal
    virtual
    override(StakerUpgradeable, StakerCapDepositsUpgradeable)
  {
    StakerCapDepositsUpgradeable._stakeMore(deposit, _depositId, _amount);
  }
}
