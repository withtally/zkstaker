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
  /// @notice Retrieves the validator information for a given validator owner.
  /// @dev This function is included in the extended interface to make it easier to access validator
  /// details directly. This is important for tasks that need to check and confirm the status and
  /// attributes of a validator.
  /// @param _validatorOwner The address of the validator owner whose information is being queried.
  /// @return _validator A struct containing the validator's details, including status and other
  /// relevant attributes.
  function validators(address _validatorOwner) external returns (Validator memory _validator);

  /// @notice Retrieves the current validator commit number.
  /// @dev This function is used to track the number of validator commits.
  /// @return The current validator commit number.
  function validatorsCommit() external view returns (uint64);

  /// @notice Retrieves the current committee activation delay.
  /// @dev This function is used to track the delay before a committee commit becomes active.
  /// @return The current committee activation delay.
  function committeeActivationDelay() external view returns (uint256);

  /// @notice Retrieves the current leader selection configuration.
  /// @dev This function is used to track the leader selection configuration.
  /// @return The current leader selection configuration.
  function leaderSelection() external view returns (LeaderSelection memory);
}
