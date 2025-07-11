// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IConsensusRegistry} from "src/interfaces/IConsensusRegistry.sol";

contract ConsensusRegistryMock is IConsensusRegistry {
  /// @dev A mapping of validator owners => validators.
  mapping(address => Validator) private _validators;

  function validators(address _validatorOwner)
    external
    view
    override
    returns (Validator memory _validator)
  {
    return _validators[_validatorOwner];
  }

  function add(
    address _validator,
    bool _isLeaderDefault,
    uint32 _weight,
    BLS12_381PublicKey calldata _validatorPubKey,
    BLS12_381Signature calldata _validatorPoP
  ) external {
    _validators[_validator] = Validator({
      ownerIdx: 0, // Assuming a default value for ownerIdx
      lastSnapshotCommit: 0, // Assuming a default value for lastSnapshotCommit
      previousSnapshotCommit: 0, // Assuming a default value for previousSnapshotCommit
      latest: ValidatorAttr({
        active: true, // Assuming the validator is active by default
        removed: false,
        leader: _isLeaderDefault,
        weight: _weight,
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
      previousSnapshot: ValidatorAttr({
        active: false,
        removed: false,
        leader: false,
        weight: 0,
        pubKey: BLS12_381PublicKey({a: bytes32(0), b: bytes32(0), c: bytes32(0)}),
        proofOfPossession: BLS12_381Signature({a: bytes32(0), b: bytes16(0)})
      })
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

  function remove(address _validatorOwner) external {}

  function changeValidatorActive(address _validatorOwner, bool _isActive) external {}

  function changeValidatorLeader(address _validatorOwner, bool _isLeader) external {}

  function changeValidatorWeight(address _validatorOwner, uint32 _weight) external {}

  function commitValidatorCommittee() external {}

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
  function setCommitteeActivationDelay(uint256 _delay) external {}

  function updateLeaderSelection(uint64 _frequency, bool _weighted) external {}
}
