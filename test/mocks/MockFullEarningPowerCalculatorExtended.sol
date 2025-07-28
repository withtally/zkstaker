// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {MockFullEarningPowerCalculator} from "staker-test/mocks/MockFullEarningPowerCalculator.sol";
import {ZkStaker} from "src/ZkStaker.sol";

contract MockFullEarningPowerCalculatorExtended is MockFullEarningPowerCalculator {
  address validatorForAtomicEarningPowerCalculation;
  bool isTestingValidatorForAtomicEarningPowerCalculation;
  ZkStaker zkStaker;

  error ValidatorForAtomicEarningPowerCalculationMismatch(address _expected, address _actual);

  function getNewEarningPower(uint256 _amountStaked, address _delegatee)
    external
    view
    returns (uint256 _newEarningPower, bool _isQualifiedForBump)
  {
    if (isTestingValidatorForAtomicEarningPowerCalculation) {
      if (
        validatorForAtomicEarningPowerCalculation
          != zkStaker.validatorForAtomicEarningPowerCalculation()
      ) {
        revert ValidatorForAtomicEarningPowerCalculationMismatch(
          validatorForAtomicEarningPowerCalculation,
          zkStaker.validatorForAtomicEarningPowerCalculation()
        );
      }
    }
    (_newEarningPower, _isQualifiedForBump) = __getEarningPower(_amountStaked, _delegatee);
  }

  function __setZkStakerAndTestValidatorExpectedForAtomicEarningPowerCalculation(
    ZkStaker _zkStaker,
    address _validator
  ) public {
    zkStaker = _zkStaker;
    isTestingValidatorForAtomicEarningPowerCalculation = true;
    validatorForAtomicEarningPowerCalculation = _validator;
  }
}
