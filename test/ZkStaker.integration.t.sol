// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Staker, ZkStaker} from "src/ZkStaker.sol";
import {IntegrationTest} from "test/helpers/IntegrationTest.sol";
import {IConsensusRegistry} from
  "lib/era-contracts/l2-contracts/contracts/interfaces/IConsensusRegistry.sol";
import {PercentAssertions} from "staker-test/helpers/PercentAssertions.sol";

contract Stake is IntegrationTest, PercentAssertions {
  function testFuzz_AddsValidatorToRegistryWhenValidatorWeightIsAboveThreshold(
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
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);

    vm.startPrank(_depositor);
    govToken.approve(address(zkStaker), _amount);
    zkStaker.stake(_amount, _delegatee, _claimer, _validatorOwner);
    vm.stopPrank();

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _validatorPubKey);
    assertEq(_latest.proofOfPossession, _validatorPoP);
  }

  function testFuzz_UpdatesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);
    assertEq(_latest.weight, _bonusWeightBelowThreshold + _amount);
  }
}

contract StakeMore is IntegrationTest {
  function testFuzz_AddsValidatorToRegistryWhenValidatorWeightIsAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _validatorPubKey);
    assertEq(_latest.proofOfPossession, _validatorPoP);
    assertEq(_latest.weight, _amount + _stakeMoreAmountAboveThreshold);
  }
}

contract Withdraw is IntegrationTest {
  function testFuzz_UpdatesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);
    assertEq(_latest.weight, _stakeAmount - _withdrawAmount);
  }

  function testFuzz_RemovesValidatorFromRegistryWhenValidatorIsAlreadyRegisteredButBelowThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);
    assertEq(_latest.removed, true);
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);
    IConsensusRegistry.BLS12_381PublicKey memory _pubKey = _latest.pubKey;
    IConsensusRegistry.BLS12_381Signature memory _pop = _latest.proofOfPossession;
    assertEq(_isEmptyBLS12_381PublicKey(_pubKey), true);
    assertEq(_isEmptyBLS12_381Signature(_pop), true);
  }
}

contract AlterValidator is IntegrationTest {
  function testFuzz_AddsValidatorToRegistryWhenValidatorIsNotRegisteredAndAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validator);
    assertEq(_latest.weight, _stakeAmountAboveThreshold);
  }

  // TODO: this will revert with ZeroValidatorWeight. Given our current design, a depositor cannot
  // alter validator if the validator have no bonus weight or other depositors.
  function testFuzz_ChangesValidatorWeightOnRegistryWhenValidatorIsAlreadyRegistered(
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
    vm.skip(true);
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

    IConsensusRegistry.ValidatorAttr memory _previousValidatorLatest =
      _getValidatorLatestAttributes(_validator);
    IConsensusRegistry.ValidatorAttr memory _currentValidatorLatest =
      _getValidatorLatestAttributes(_newValidator);
    assertEq(_previousValidatorLatest.weight, 0);
    assertEq(_currentValidatorLatest.weight, _amount + _bonusWeightAboveThreshold);
  }

  // TODO: Likewise, there may be cases where a single depositor is the sole contributor to a
  // validator, but the validator cannot be removed with alterValidator, because that will cause
  // revert with ZeroValidatorWeight.
  function testFuzz_RemovesValidatorFromRegistryWhenValidatorRegisteredButBelowThreshold(
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
    vm.skip(true);
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validator);
    assertEq(_latest.removed, true);
  }
}

contract SetBonusWeight is IntegrationTest {
  function testFuzz_AddsValidatorToRegistryWhenBonusWeightIsAboveThreshold(
    address _validatorOwner,
    uint256 _bonusWeightAboveThreshold,
    IConsensusRegistry.BLS12_381PublicKey calldata _validatorPubKey,
    IConsensusRegistry.BLS12_381Signature calldata _validatorPoP
  ) public {
    _assumeValidKeys(_validatorPubKey, _validatorPoP);
    _registerValidator(_validatorOwner, _validatorPubKey, _validatorPoP);
    _bonusWeightAboveThreshold =
      _boundAndSetBonusWeightAboveThreshold(_validatorOwner, _bonusWeightAboveThreshold);

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);
    assertEq(_latest.weight, _bonusWeightAboveThreshold);
  }
}

contract ChangeValidatorKey is IntegrationTest {
  function testFuzz_RegistersValidatorAsOwnerOnTheRegistryWhenAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _validatorPubKey);
    assertEq(_latest.proofOfPossession, _validatorPoP);
  }

  function testFuzz_RegistersValidatorAsValidatorStakeAuthorityOnTheRegistryWhenAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _validatorPubKey);
    assertEq(_latest.proofOfPossession, _validatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsOwnerOnTheRegistryWhenAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _newValidatorPubKey);
    assertEq(_latest.proofOfPossession, _newValidatorPoP);
  }

  function testFuzz_ChangesValidatorKeysAsStakeAuthorityOnTheRegistryWhenAboveThreshold(
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validatorOwner);

    assertEq(_latest.pubKey, _newValidatorPubKey);
    assertEq(_latest.proofOfPossession, _newValidatorPoP);
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

    IConsensusRegistry.ValidatorAttr memory _latest = _getValidatorLatestAttributes(_validator);
    assertEq(_latest.leader, true);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller, address _validator) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.changeValidatorLeader(_validator, true);
  }
}

contract SetCommitteeActivationDelay is IntegrationTest {
  function testFuzz_SetsCommitteeActivationDelay(uint256 _delay) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.setCommitteeActivationDelay(_delay);

    assertEq(CONSENSUS_REGISTRY.committeeActivationDelay(), _delay);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(address _caller, uint256 _delay) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.setCommitteeActivationDelay(_delay);
  }
}

contract UpdateLeaderSelection is IntegrationTest {
  function testFuzz_UpdatesLeaderSelection(uint64 _frequency, bool _weighted) public {
    vm.prank(validatorStakeAuthority);
    zkStaker.updateLeaderSelection(_frequency, _weighted);
    (IConsensusRegistry.LeaderSelectionAttr memory _latest,,,,) =
      CONSENSUS_REGISTRY.leaderSelection();

    assertEq(_latest.frequency, _frequency);
    assertEq(_latest.weighted, _weighted);
  }

  function testFuzz_RevertIf_NotValidatorStakeAuthority(
    address _caller,
    uint64 _frequency,
    bool _weighted
  ) public {
    vm.assume(_caller != validatorStakeAuthority);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        Staker.Staker__Unauthorized.selector, bytes32("not validator stake authority"), _caller
      )
    );
    zkStaker.updateLeaderSelection(_frequency, _weighted);
  }
}
