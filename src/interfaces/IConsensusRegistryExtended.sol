// SPDX-License-Identifier: MIT
// We use a floating point pragma here so it can be used within other projects that interact with
// the ZKsync ecosystem without using our exact pragma version.
pragma solidity ^0.8.20;

import {IConsensusRegistry} from
  "lib/era-contracts/l2-contracts/contracts/interfaces/IConsensusRegistry.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @title ConsensusRegistry contract interface
interface IConsensusRegistryExtended is IConsensusRegistry {
  function validators(address _validatorOwner) external returns (Validator memory _validator);
}
