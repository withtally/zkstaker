// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {IConsensusRegistryExtended} from "src/interfaces/IConsensusRegistryExtended.sol";
import {ZkStakerTestBase} from "test/ZkStaker.t.sol";
import {IConsensusRegistry} from
  "lib/era-contracts/l2-contracts/contracts/interfaces/IConsensusRegistry.sol";
import {ConsensusRegistry} from "era-contracts/l2-contracts/contracts/ConsensusRegistry.sol";

contract IntegrationTest is ZkStakerTestBase {
  ConsensusRegistry CONSENSUS_REGISTRY;

  function setUp() public virtual override {
    super.setUp();

    // TODO: deploy mock identity earning power calculator that can be used to assert on our temp
    // storage var
    // calculator = new IdentityEarningPowerCalculator();

    CONSENSUS_REGISTRY = new ConsensusRegistry();
    CONSENSUS_REGISTRY.initialize(address(zkStaker));
    vm.prank(admin);
    zkStaker.setRegistry(IConsensusRegistryExtended(address(CONSENSUS_REGISTRY)));
  }

  function _getValidatorLatestAttributes(address _depositor)
    internal
    view
    returns (IConsensusRegistry.ValidatorAttr memory _latest)
  {
    (, _latest,,,,) = CONSENSUS_REGISTRY.validators(_depositor);
  }

  function _registerValidatorWithBonusWeightAboveThreshold(
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    uint256 _bonusWeightAboveThreshold
  ) internal returns (uint256 boundedBonusWeightAboveThreshold) {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    boundedBonusWeightAboveThreshold =
      _boundAndSetBonusWeightAboveThreshold(_validator, _bonusWeightAboveThreshold);
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
  }
}
