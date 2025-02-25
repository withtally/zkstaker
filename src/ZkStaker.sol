// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Staker, IERC20} from "staker/src/Staker.sol";
import {StakerPermitAndStake} from "staker/src/extensions/StakerPermitAndStake.sol";
import {StakerOnBehalf, EIP712} from "staker/src/extensions/StakerOnBehalf.sol";
import {StakerDelegateSurrogateVotes} from "staker/src/extensions/StakerDelegateSurrogateVotes.sol";
import {IERC20Staking} from "staker/src/interfaces/IERC20Staking.sol";
import {IEarningPowerCalculator} from "staker/src/interfaces/IEarningPowerCalculator.sol";

// this import was needed to get hardhat to include the calculators into the zk-artifacts so the
// deploy script could find them
import {IdentityEarningPowerCalculator} from
  "staker/src/calculators/IdentityEarningPowerCalculator.sol";

/// @title ZkStaker
/// @author [ScopeLift](https://scopelift.co)
/// @notice A staking contract for ZK Nation that extends the Staker contract from
/// withtally/staker. This implementation includes permit functionality for gasless approvals,
/// staking on behalf of other addresses, and delegation of voting power through surrogate
/// contracts.
/// @dev This contract combines multiple extension modules from the base Staker.
contract ZkStaker is Staker, StakerPermitAndStake, StakerOnBehalf, StakerDelegateSurrogateVotes {
  /// @notice Initializes the ZkStaker contract with required parameters.
  /// @param _rewardsToken ERC20 token in which rewards will be denominated.
  /// @param _stakeToken Delegable governance token which users will stake to earn rewards.
  /// @param _earningPowerCalculator The contract that will calculate earning power for stakers.
  /// @param _maxBumpTip Maximum tip that can be paid to bumpers for updating earning power.
  /// @param _admin Address which will have permission to manage reward notifiers.
  /// @param _name Name used in the EIP712 domain separator for permit functionality.
  constructor(
    IERC20 _rewardsToken,
    IERC20Staking _stakeToken,
    IEarningPowerCalculator _earningPowerCalculator,
    uint256 _maxBumpTip,
    address _admin,
    string memory _name
  )
    Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
    StakerPermitAndStake(_stakeToken)
    StakerDelegateSurrogateVotes(_stakeToken)
    EIP712(_name, "1")
  {
    MAX_CLAIM_FEE = 1e18;
    _setClaimFeeParameters(ClaimFeeParameters({feeAmount: 0, feeCollector: address(0)}));
  }
}
