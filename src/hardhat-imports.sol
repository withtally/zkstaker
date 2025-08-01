// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

// these imports needed to get hardhat to include the contracts into the zk-artifacts so the
// deploy script could find them
import {IdentityEarningPowerCalculator} from "staker/calculators/IdentityEarningPowerCalculator.sol";
import {MintRewardNotifier} from "staker/notifiers/MintRewardNotifier.sol";
