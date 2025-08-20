// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ZkStaker, IERC20} from "src/ZkStaker.sol";
import {IERC20Staking} from "staker/interfaces/IERC20Staking.sol";
import {IdentityEarningPowerCalculator} from "staker/calculators/IdentityEarningPowerCalculator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IntegrationTest is Test {
  address constant ZK_TOKEN_ADDRESS = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  string constant ZKSYNC_RPC_URL = "https://mainnet.era.zksync.io";
  ZkStaker zkStaker;
  IdentityEarningPowerCalculator calculator;
  // ArbitrumDeploy deployScript;
  uint256 constant REWARD_DURATION = 30 days;
  uint256 constant SCALE_FACTOR = 1e36;

  function setUp() public virtual {
    (string memory rpcUrl, uint256 forkBlock) = _getForkConfig();
    vm.createSelectFork(rpcUrl, forkBlock);

    calculator = new IdentityEarningPowerCalculator();
    ZkStaker implementation = new ZkStaker();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(implementation),
      abi.encodeCall(
        ZkStaker.initialize,
        (
          IERC20(ZK_TOKEN_ADDRESS), // reward token
          IERC20Staking(ZK_TOKEN_ADDRESS), // stake token
          0, // max claim fee
          address(this), // admin
          1e18, // max bump tip
          calculator, // earning power calculator
          "ZkStaker", // name
          1e24 // stake cap
        )
      )
    );
	zkStaker = ZkStaker(address(proxy));
  }

  function _dealStakingToken(address _recipient, uint96 _amount) internal returns (uint96) {
    // Bound amount to reasonable values
    _amount = uint96(bound(_amount, 0.1e18, 250_000_000e18));
    deal(address(zkStaker.STAKE_TOKEN()), _recipient, _amount);
    return _amount;
  }

  function _jumpAheadByPercentOfRewardDuration(uint256 _percent) internal {
    _percent = bound(_percent, 0, 100);
    vm.warp(block.timestamp + (REWARD_DURATION * _percent) / 100);
  }

  function _boundToRealisticReward(uint256 _rewardAmount) internal pure returns (uint256) {
    // Use much more conservative bounds to prevent overflow
    return bound(_rewardAmount, 1e18, 1_000_000e18); // Max 1M tokens
  }

  function _mintTransferAndNotifyReward(uint256 _rewardAmount) internal {
    // Bound the reward amount to realistic values
    _rewardAmount = _boundToRealisticReward(_rewardAmount);

    // Get the admin from the deployment script
    address admin = zkStaker.admin();
    address rewardNotifier = makeAddr("rewardNotifier");

    // Set up the reward notifier
    vm.prank(admin);
    zkStaker.setRewardNotifier(rewardNotifier, true);

    // Use deal with the bounded amount
    deal(address(zkStaker.REWARD_TOKEN()), rewardNotifier, _rewardAmount);

    // Transfer tokens to the staking contract and notify
    vm.startPrank(rewardNotifier);
    IERC20(address(zkStaker.REWARD_TOKEN())).transfer(address(zkStaker), _rewardAmount);
    zkStaker.notifyRewardAmount(_rewardAmount);
    vm.stopPrank();
  }

  function _boundEligibilityScore(uint256 _score) internal pure returns (uint256) {
    return bound(_score, 50, 100);
  }

  /// @notice Internal function to get fork configuration with default values
  /// @return rpcUrl The RPC URL to use for forking
  /// @return forkBlock The block number to fork from
  function _getForkConfig() internal view returns (string memory rpcUrl, uint256 forkBlock) {
    // Get RPC URL with default fallback
    try vm.envString("RPC_URL") returns (string memory envRpcUrl) {
      rpcUrl = envRpcUrl;
    } catch {
      rpcUrl = "https://sepolia.era.zksync.dev/";
    }

    // Get fork block with default fallback
    try vm.envUint("FORK_BLOCK") returns (uint256 envForkBlock) {
      forkBlock = envForkBlock;
    } catch {
      forkBlock = 5_573_532;
    }
  }
}
