// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {
  IConsensusRegistryExtended,
  IConsensusRegistry
} from "src/interfaces/IConsensusRegistryExtended.sol";

contract ConsensusRegistryMock is IConsensusRegistryExtended {
  /// @dev A mapping of validator owners => validators.
  mapping(address => Validator) private _validators;

  uint64 private _validatorsCommit;

  uint256 private _committeeActivationDelay;

  LeaderSelection private _leaderSelection;

  function validators(address _validatorOwner) external view returns (Validator memory _validator) {
    return _validators[_validatorOwner];
  }

  function validatorsCommit() external view returns (uint64) {
    return _validatorsCommit;
  }

  function committeeActivationDelay() external view returns (uint256) {
    return _committeeActivationDelay;
  }

  function leaderSelection() external view returns (LeaderSelection memory) {
    return _leaderSelection;
  }

  function add(
    address _validatorOwner,
    bool _validatorIsLeader,
    bool _validatorIsActive,
    uint256 _validatorWeight,
    BLS12_381PublicKey calldata _validatorPubKey,
    BLS12_381Signature calldata _validatorPoP
  ) external {
    _validators[_validatorOwner] = Validator({
      ownerIdx: 0, // Assuming a default value for ownerIdx
      latest: ValidatorAttr({
        active: _validatorIsActive,
        removed: false,
        leader: _validatorIsLeader,
        weight: _validatorWeight,
        pubKey: _validatorPubKey,
        proofOfPossession: _validatorPoP
      }),
      snapshot: ValidatorAttr({
        active: false,
        removed: false,
        leader: false,
        weight: 0,
        pubKey: BLS12_381PublicKey({a: bytes32(0), b: bytes32(0), c: bytes32(0)}),
        proofOfPossession: BLS12_381Signature({a: bytes32(0), b: bytes16(0)})
      }),
      snapshotCommit: 0,
      previousSnapshot: ValidatorAttr({
        active: false,
        removed: false,
        leader: false,
        weight: 0,
        pubKey: BLS12_381PublicKey({a: bytes32(0), b: bytes32(0), c: bytes32(0)}),
        proofOfPossession: BLS12_381Signature({a: bytes32(0), b: bytes16(0)})
      }),
      previousSnapshotCommit: 0
    });
  }

  function changeValidatorKey(
    address _validatorOwner,
    BLS12_381PublicKey calldata _pubKey,
    BLS12_381Signature calldata _pop
  ) external {
    _validators[_validatorOwner].latest.pubKey = _pubKey;
    _validators[_validatorOwner].latest.proofOfPossession = _pop;
  }

  function changeValidatorWeight(address _validatorOwner, uint256 _weight) external {
    _validators[_validatorOwner].latest.weight = _weight;
  }

  function remove(address _validatorOwner) external {
    _validators[_validatorOwner].latest.removed = true;
  }

  function changeValidatorActive(address _validatorOwner, bool _isActive) external {}

  function changeValidatorLeader(address _validatorOwner, bool _isLeader) external {
    _validators[_validatorOwner].latest.leader = _isLeader;
  }

  function commitValidatorCommittee() external {
    _validatorsCommit++;
  }

  function getValidatorCommittee()
    external
    view
    returns (CommitteeValidator[] memory, LeaderSelectionAttr memory)
  {}

  function getNextValidatorCommittee()
    external
    view
    returns (CommitteeValidator[] memory, LeaderSelectionAttr memory)
  {}

  function setCommitteeActivationDelay(uint256 _delay) external {
    _committeeActivationDelay = _delay;
  }

  function updateLeaderSelection(uint64 _frequency, bool _weighted) external {
    _leaderSelection.latest = LeaderSelectionAttr({frequency: _frequency, weighted: _weighted});
  }
}
