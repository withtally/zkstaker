// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Staker, ZkStaker} from "src/ZkStaker.sol";
import {IConsensusRegistry} from
  "era-contracts/l2-contracts/contracts/interfaces/IConsensusRegistry.sol";
import {ConsensusRegistry} from "era-contracts/l2-contracts/contracts/ConsensusRegistry.sol";
import {PercentAssertions} from "staker-test/helpers/PercentAssertions.sol";
import {IConsensusRegistryExtended} from "src/interfaces/IConsensusRegistryExtended.sol";
import {ZkStakerTestBase} from "test/ZkStaker.t.sol";

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

  function _getValidatorOnRegistry(address _validator)
    internal
    view
    returns (IConsensusRegistry.ValidatorAttr memory _latest)
  {
    (, _latest,,,,) = CONSENSUS_REGISTRY.validators(_validator);
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

contract Stake is IntegrationTest, PercentAssertions {
  function testFuzz_AddsValidatorToRegistry(
    address _depositor,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _amount);

    // Register validator on ZkStaker
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    // assert that validator is not on ConsensusRegistry
    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    assertEq(_validator.pubKey, IConsensusRegistry.BLS12_381PublicKey(0, 0, 0));
    assertEq(_validator.proofOfPossession, IConsensusRegistry.BLS12_381Signature(0, 0));

    // Stake to validator, adding it to ConsensusRegistry
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    // assert that validator is on ConsensusRegistry
    _validator = _getValidatorOnRegistry(_validatorOwner);
    assertEq(_validator.pubKey, _validatorPubKey);
    assertEq(_validator.proofOfPossession, _validatorPoP);
  }

  function testFuzz_UpdatesValidatorWeightOnRegistry(
    address _depositor,
    uint256 _bonusWeightAboveThreshold,
    uint256 _bonusWeightBelowThreshold,
    uint256 _amount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _amount);

    _bonusWeightAboveThreshold = _registerValidatorWithBonusWeightAboveThreshold(
      _validatorOwner, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );
    _bonusWeightBelowThreshold =
      _boundAndSetBonusWeightBelowThreshold(_validatorOwner, _bonusWeightBelowThreshold);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    assertEq(_validator.weight, _bonusWeightBelowThreshold + _amount);
  }
}

contract StakeMore is IntegrationTest {
  function testFuzz_AddsValidatorToRegistry(
    address _depositor,
    uint256 _amount,
    uint256 _stakeMoreAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _amount = _boundAndMintGovToken(_depositor, _amount);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    ZkStaker.DepositIdentifier _depositId;
    _amount = bound(_amount, 0, initialValidatorWeightThreshold - 1);
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validatorOwner);

    _stakeMoreAmountAboveThreshold = bound(
      _stakeMoreAmountAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _mintGovToken(_depositor, _stakeMoreAmountAboveThreshold);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _stakeMoreAmountAboveThreshold);
    zkStaker.stakeMore(_depositId, _stakeMoreAmountAboveThreshold);
    vm.stopPrank();

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);

    assertEq(_validator.pubKey, _validatorPubKey);
    assertEq(_validator.proofOfPossession, _validatorPoP);
    assertEq(_validator.weight, _amount + _stakeMoreAmountAboveThreshold);
  }
}

contract Withdraw is IntegrationTest {
  function testFuzz_UpdatesValidatorWeightOnRegistry(
    address _depositor,
    uint256 _stakeAmount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validatorOwner != address(0));
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _stakeAmount = bound(
      _stakeAmount,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (_stakeAmount, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmount, _delegatee, _claimer, _validatorOwner);
    _withdrawAmount = bound(_withdrawAmount, 0, _stakeAmount - 1);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    assertValidatorRemovedOrWeightIfAboveThreshold(_validator, _stakeAmount - _withdrawAmount);
  }

  function testFuzz_RemovesValidatorFromRegistry(
    address _depositor,
    uint256 _stakeAmount,
    uint256 _withdrawAmount,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validatorOwner != address(0));
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _stakeAmount = bound(
      _stakeAmount,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (_stakeAmount, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmount, _delegatee, _claimer, _validatorOwner);
    _withdrawAmount =
      bound(_withdrawAmount, _stakeAmount - initialValidatorWeightThreshold + 1, _stakeAmount - 1);

    vm.prank(_depositor);
    zkStaker.withdraw(_depositId, _withdrawAmount);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    assertEq(_validator.removed, true);
  }

  function testFuzz_DoesNotAddValidatorToRegistryWhenValidatorWeightIsBelowThreshold(
    address _depositor,
    uint256 _amount,
    uint256 _stakeMoreAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validatorOwner,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _amount = _boundAndMintGovToken(_depositor, _amount);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    ZkStaker.DepositIdentifier _depositId;
    _amount = bound(_amount, 0, initialValidatorWeightThreshold - 1);
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validatorOwner);

    _stakeMoreAmountAboveThreshold =
      bound(_stakeMoreAmountAboveThreshold, 0, initialValidatorWeightThreshold - _amount - 1);
    _mintGovToken(_depositor, _stakeMoreAmountAboveThreshold);
    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _stakeMoreAmountAboveThreshold);
    zkStaker.stakeMore(_depositId, _stakeMoreAmountAboveThreshold);
    vm.stopPrank();

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _validator.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _validator.proofOfPossession;
    assertEq(_isEmptyBLS12_381PublicKey(_pubKey), true);
    assertEq(_isEmptyBLS12_381Signature(_pop), true);
  }
}

contract AlterValidator is IntegrationTest {
  function testFuzz_AddsValidatorToRegistry(
    address _depositor,
    uint256 _stakeAmountAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _stakeAmountAboveThreshold = bound(
      _stakeAmountAboveThreshold,
      initialValidatorWeightThreshold,
      zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    ZkStaker.DepositIdentifier _depositId;
    (, _depositId) =
      _boundMintAndStake(_depositor, _stakeAmountAboveThreshold, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _validator);

    IConsensusRegistry.ValidatorAttr memory _validatorOnRegistry =
      _getValidatorOnRegistry(_validator);
    assertEq(_validatorOnRegistry.weight, _stakeAmountAboveThreshold);
  }

  function testFuzz_ChangesValidatorWeightOnRegistry(
    address _depositor,
    uint256 _amount,
    uint256 _bonusWeightAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != _newValidator);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold = _registerValidatorWithBonusWeightAboveThreshold(
      _newValidator, _newValidatorPubKey, _newValidatorPoP, _bonusWeightAboveThreshold
    );
    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    IConsensusRegistry.ValidatorAttr memory _previousValidator = _getValidatorOnRegistry(_validator);
    IConsensusRegistry.ValidatorAttr memory _currentValidator =
      _getValidatorOnRegistry(_newValidator);
    assertValidatorRemovedOrWeightIfAboveThreshold(_previousValidator, 0);
    assertEq(_currentValidator.weight, _amount + _bonusWeightAboveThreshold);
  }

  function testFuzz_RemovesValidatorFromRegistry(
    address _depositor,
    uint256 _amount,
    uint256 _bonusWeightAboveThreshold,
    address _delegatee,
    address _claimer,
    address _validator,
    address _newValidator,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _assumeValidDelegateeAndClaimer(_delegatee, _claimer);
    vm.assume(_validator != _newValidator);
    _amount = bound(
      _amount, initialValidatorWeightThreshold, zkStaker.totalStakeCap() - zkStaker.totalStaked()
    );
    _registerValidator(_validator, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold = _registerValidatorWithBonusWeightAboveThreshold(
      _newValidator, _newValidatorPubKey, _newValidatorPoP, _bonusWeightAboveThreshold
    );
    ZkStaker.DepositIdentifier _depositId;
    (_amount, _depositId) =
      _boundMintAndStake(_depositor, _amount, _delegatee, _claimer, _validator);

    vm.prank(_depositor);
    zkStaker.alterValidator(_depositId, _newValidator);

    IConsensusRegistry.ValidatorAttr memory _validatorOnRegistry =
      _getValidatorOnRegistry(_validator);
    assertEq(_validatorOnRegistry.removed, true);
  }
}

contract SetBonusWeight is IntegrationTest {
  function testFuzz_AddsValidatorToRegistry(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold =
      _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);
    assertEq(_validator.weight, _bonusWeightAboveThreshold);
  }
}

contract ChangeValidatorKey is IntegrationTest {
  function testFuzz_AddsValidatorAsOwnerOnTheRegistry(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);

    assertEq(_validator.pubKey, _validatorPubKey);
    assertEq(_validator.proofOfPossession, _validatorPoP);
  }

  function testFuzz_AddsValidatorAsValidatorStakeAuthorityOnTheRegistry(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);

    assertEq(_validator.pubKey, _validatorPubKey);
    assertEq(_validator.proofOfPossession, _validatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsOwnerOnTheRegistry(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);

    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _newValidatorPubKey, _newValidatorPoP);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);

    assertEq(_validator.pubKey, _newValidatorPubKey);
    assertEq(_validator.proofOfPossession, _newValidatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsStakeAuthorityOnTheRegistry(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP,
    IConsensusRegistry.BLS12_381PublicKey calldata _newValidatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _newValidatorPoP
  ) public {
    _bonusWeightAboveThreshold =
      bound(_bonusWeightAboveThreshold, initialValidatorWeightThreshold, type(uint256).max);

    vm.prank(validatorStakeAuthority);
    zkStaker.setBonusWeight(_validatorOwner, _bonusWeightAboveThreshold);

    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _assumeValidKeys(_newValidatorPubKey, _newValidatorPoP);
    vm.prank(_validatorOwner);
    zkStaker.changeValidatorKey(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorKey(_validatorOwner, _newValidatorPubKey, _newValidatorPoP);

    IConsensusRegistry.ValidatorAttr memory _validator = _getValidatorOnRegistry(_validatorOwner);

    assertEq(_validator.pubKey, _newValidatorPubKey);
    assertEq(_validator.proofOfPossession, _newValidatorPoP);
  }
}

contract ChangeValidatorLeader is IntegrationTest {
  function testFuzz_ChangesValidatorLeader(
    address _validator,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    vm.assume(_validator != address(this));

    _registerValidatorWithBonusWeightAboveThreshold(
      _validator, _validatorPubKey, _validatorPoP, _bonusWeightAboveThreshold
    );

    vm.prank(validatorStakeAuthority);
    zkStaker.changeValidatorLeader(_validator, true);

    IConsensusRegistry.ValidatorAttr memory _validatorOnRegistry =
      _getValidatorOnRegistry(_validator);
    assertEq(_validatorOnRegistry.leader, true);
  }
}

contract SetCommitteeActivationDelay is IntegrationTest {
  function testFuzz_SetsCommitteeActivationDelay(uint256 _delay) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.setCommitteeActivationDelay(_delay);

    assertEq(CONSENSUS_REGISTRY.committeeActivationDelay(), _delay);
  }
}

contract UpdateLeaderSelection is IntegrationTest {
  function testFuzz_UpdatesLeaderSelection(uint64 _frequency, bool _weighted) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.updateLeaderSelection(_frequency, _weighted);
    (IConsensusRegistry.LeaderSelectionAttr memory _validator,,,,) =
      CONSENSUS_REGISTRY.leaderSelection();

    assertEq(_validator.frequency, _frequency);
    assertEq(_validator.weighted, _weighted);
  }
}
