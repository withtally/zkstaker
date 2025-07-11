// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IConsensusRegistry} from "src/interfaces/IConsensusRegistry.sol";

contract ConsensusRegistryMock is IConsensusRegistry {
  function validators(address _validatorOwner) external returns (Validator memory _validator) {}

  function add(
    address _validator,
    bool _isLeaderDefault,
    uint32 _weight,
    BLS12_381PublicKey calldata _validatorPubKey,
    BLS12_381Signature calldata _validatorPoP
  ) external {}

  function remove(address _validatorOwner) external {}

  function changeValidatorActive(address _validatorOwner, bool _isActive) external {}

  function changeValidatorLeader(address _validatorOwner, bool _isLeader) external {}

  function changeValidatorKey(
    address _validatorOwner,
    BLS12_381PublicKey calldata _pubKey,
    BLS12_381Signature calldata _pop
  ) external {}

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
