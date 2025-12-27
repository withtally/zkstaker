// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZkStaker, IERC20, IEarningPowerCalculator} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {ERC20Fake} from "staker-test/fakes/ERC20Fake.sol";
import {ERC20VotesMock} from "staker-test/mocks/MockERC20Votes.sol";
import {MockFullEarningPowerCalculator} from "staker-test/mocks/MockFullEarningPowerCalculator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakerUpgradeable} from "staker/StakerUpgradeable.sol";

contract ZkStakerTestBase is Test {
  ERC20Fake rewardToken;
  ERC20VotesMock govToken;
  MockFullEarningPowerCalculator earningPowerCalculator;
  ZkStaker zkStaker;

  address admin;
  uint256 maxBumpTip;
  uint256 initialTotalStakeCap;
  string name;

  function setUp() public virtual {
    rewardToken = new ERC20Fake();
    govToken = new ERC20VotesMock();
    earningPowerCalculator = new MockFullEarningPowerCalculator();
    admin = makeAddr("admin");
    maxBumpTip = 1e18;
    initialTotalStakeCap = 1e24;
    name = "ZkStaker";
  }

  function _deployStaker() public virtual returns (StakerUpgradeable _staker) {
    ZkStaker implementation = new ZkStaker();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(implementation),
      abi.encodeCall(
        ZkStaker.initialize,
        (
          rewardToken, // reward token
          govToken, // stake token
          0, // max claim fee
          admin, // admin
          maxBumpTip, // max bump tip
          earningPowerCalculator, // earning power calculator
          "Staker", // name
          initialTotalStakeCap // stake cap
        )
      )
    );
    return ZkStaker(address(proxy));
  }

  function _deployStaker(
    IERC20 _rewardToken,
    IERC20 _stakeToken,
    uint256 _maxClaimFee,
    address _admin,
    uint256 _maxBumpTip,
    IEarningPowerCalculator _earningPowerCalculator,
    string memory _name,
    uint256 _initialTotalStakeCap
  ) public virtual returns (StakerUpgradeable _staker) {
    ZkStaker implementation = new ZkStaker();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(implementation),
      abi.encodeCall(
        ZkStaker.initialize,
        (
          _rewardToken, // reward token
          _stakeToken, // stake token
          _maxClaimFee, // max claim fee
          _admin, // admin
          _maxBumpTip, // max bump tip
          _earningPowerCalculator, // earning power calculator
          _name, // name
          _initialTotalStakeCap // stake cap
        )
      )
    );
    return ZkStaker(address(proxy));
  }

  /// @dev Helper function to validate addresses for fuzz tests
  function _validateAddresses(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    address _admin
  ) internal pure {
    // Ensure no zero addresses
    vm.assume(_rewardToken != address(0));
    vm.assume(_stakeToken != address(0));
    vm.assume(_earningPowerCalculator != address(0));
    vm.assume(_admin != address(0));

    // Ensure addresses are different
    vm.assume(_rewardToken != _stakeToken);
    vm.assume(_rewardToken != _earningPowerCalculator);
    vm.assume(_stakeToken != _earningPowerCalculator);
  }
}

contract Constructor is ZkStakerTestBase {
  function test_SetsInitializationParameters() public {
    StakerUpgradeable _zkStaker = _deployStaker();

    assertEq(address(_zkStaker.REWARD_TOKEN()), address(rewardToken));
    assertEq(address(_zkStaker.STAKE_TOKEN()), address(govToken));
    assertEq(address(_zkStaker.earningPowerCalculator()), address(earningPowerCalculator));
    assertEq(_zkStaker.maxBumpTip(), maxBumpTip);
    assertEq(_zkStaker.admin(), admin);
  }

  function testFuzz_SetsTheRewardTokenStakeTokenAndOwnerToArbitraryAddresses(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxClaimFee,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    string memory _name
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    StakerUpgradeable _zkStaker = _deployStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      _maxClaimFee,
      _admin,
      _maxBumpTip,
      IEarningPowerCalculator(_earningPowerCalculator),
      _name,
      _initialTotalStakeCap
    );

    assertEq(address(_zkStaker.REWARD_TOKEN()), _rewardToken);
    assertEq(address(_zkStaker.STAKE_TOKEN()), _stakeToken);
    assertEq(address(_zkStaker.earningPowerCalculator()), _earningPowerCalculator);
    assertEq(_zkStaker.maxBumpTip(), _maxBumpTip);
    assertEq(ZkStaker(address(_zkStaker)).totalStakeCap(), _initialTotalStakeCap);
    assertEq(_zkStaker.admin(), _admin);
  }

  function testFuzz_SetsClaimFeeParameters(
    address _rewardToken,
    address _stakeToken,
    address _earningPowerCalculator,
    uint256 _maxClaimFee,
    uint256 _maxBumpTip,
    uint256 _initialTotalStakeCap,
    address _admin,
    string memory _name
  ) public {
    _validateAddresses(_rewardToken, _stakeToken, _earningPowerCalculator, _admin);

    StakerUpgradeable _zkStaker = _deployStaker(
      IERC20(_rewardToken),
      IERC20Staking(_stakeToken),
      _maxClaimFee,
      _admin,
      _maxBumpTip,
      IEarningPowerCalculator(_earningPowerCalculator),
      _name,
      _initialTotalStakeCap
    );

    assertEq(_zkStaker.MAX_CLAIM_FEE(), _maxClaimFee);
    StakerUpgradeable.ClaimFeeParameters memory _feeParams = _zkStaker.claimFeeParameters();
    assertEq(_feeParams.feeAmount, 0);
    assertEq(_feeParams.feeCollector, address(0));
  }
}
