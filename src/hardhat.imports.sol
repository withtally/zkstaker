pragma solidity ^0.8.28;

// these imports needed to get hardhat to include the contracts into the zk-artifacts so the
// deploy script could find them
import {ConsensusRegistry} from "era-contracts/l2-contracts/contracts/ConsensusRegistry.sol";
import {IdentityEarningPowerCalculator} from "staker/calculators/IdentityEarningPowerCalculator.sol";
import {MintRewardNotifier} from "staker/notifiers/MintRewardNotifier.sol";
