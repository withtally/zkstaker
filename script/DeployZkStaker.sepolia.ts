import { config as dotEnvConfig } from "dotenv";
import * as zk from 'zksync-ethers';
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, utils } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.

// EarningPowerCalculator deployment constructor arguments
const EARNING_POWER_CALCULATOR_NAME = "IdentityEarningPowerCalculator";

// Notifier deployment constructor arguments
const NUMBER_OF_SECONDS_IN_A_DAY = 86400;
const REWARD_AMOUNT = "1000000000000000000";
const REWARD_INTERVAL = 30 * NUMBER_OF_SECONDS_IN_A_DAY; // 30 days

// ZkStaker deployment constructor arguments
const ZK_TOKEN_ADDRESS = "0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96"; // Sepolia ZK Token Address
const ZK_GOV_OPS_TIMELOCK = "0xC3e970cB015B5FC36edDf293D2370ef5D00F7a19" // TODO: Find testnet Timelock address
const ZK_CAPPED_MINTER = "0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E"; // Sepolia Capped Minter Address
const MAX_BUMP_TIP = 0;
const INITIAL_TOTAL_STAKE_CAP = "1000000000000000000000000";
const STAKER_NAME = "ZkStaker";
const VALIDATOR_STAKE_AUTHORITY = "0x0000000000000000000000000000000000000000";
const INITIAL_VALIDATOR_WEIGHT_THRESHOLD = 0;
const IS_LEADER_DEFAULT = true;

const CONSENSUS_REGISTRY = "0xd2c50a9cad7F604BF42Fc0A44396F93a24661710"; // Address of the deployed consensus registry

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }
  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  // Deploy EarningPowerCalculator contract using create
  const earningPowerCalculatorName = EARNING_POWER_CALCULATOR_NAME;
  console.log("Deploying " + earningPowerCalculatorName + "...");
  const earningPowerCalculatorContractArtifact = await deployer.loadArtifact(earningPowerCalculatorName);
  const earningPowerCalculator = await deployer.deploy(earningPowerCalculatorContractArtifact, [], "create", undefined);
  await earningPowerCalculator.deploymentTransaction()?.wait();
  const earningPowerCalculaterContractAddress = await earningPowerCalculator.getAddress();
  console.log(`${earningPowerCalculatorName} was deployed to ${earningPowerCalculaterContractAddress}`);

  // Deploy ZkStaker contract using create
  const zkStakerContractName  = "ZkStaker";
  const zkStakerContractArtifact = await deployer.loadArtifact(zkStakerContractName );
  const constructorArgs = [ZK_TOKEN_ADDRESS, ZK_TOKEN_ADDRESS, earningPowerCalculaterContractAddress, MAX_BUMP_TIP, INITIAL_TOTAL_STAKE_CAP, zkWallet.address, VALIDATOR_STAKE_AUTHORITY, STAKER_NAME, INITIAL_VALIDATOR_WEIGHT_THRESHOLD, IS_LEADER_DEFAULT];
  const zkStaker = await deployer.deploy(zkStakerContractArtifact, constructorArgs, "create", undefined);
  await zkStaker.deploymentTransaction()?.wait();
  const zkStakerContractAddress = await zkStaker.getAddress();
  console.log(`${zkStakerContractName } was deployed to ${zkStakerContractAddress}`);

  // Deploy the MintRewardNotifier contract using create
  const mintRewardNotifierContractName = "MintRewardNotifier";
  const mintRewardNotifierContractArtifact = await deployer.loadArtifact(mintRewardNotifierContractName);
  const mintRewardNotifier = await deployer.deploy(mintRewardNotifierContractArtifact, [zkStakerContractAddress, REWARD_AMOUNT, REWARD_INTERVAL, ZK_GOV_OPS_TIMELOCK, ZK_CAPPED_MINTER], "create", undefined);
  await mintRewardNotifier.deploymentTransaction()?.wait();
  const mintRewardNotifierContractAddress = await mintRewardNotifier.getAddress();
  console.log(`${mintRewardNotifierContractName} was deployed to ${mintRewardNotifierContractAddress}`);

  // Set the notifier of the ZkStaker contract to the MintRewardNotifier
  await zkStaker.setRewardNotifier(mintRewardNotifierContractAddress, true);

  // Set the consensus registry of the ZkStaker contract
  await zkStaker.setRegistry(CONSENSUS_REGISTRY);
  console.log(`Registry set to ${CONSENSUS_REGISTRY}`)

  // Set the admin of the ZkStaker contract to the timelock
  await zkStaker.setAdmin(ZK_GOV_OPS_TIMELOCK);

  // Output the contract addresses to be captured by the calling script
  console.log(`ZKSTAKER_ADDRESS=${zkStakerContractAddress}\nEARNING_POWER_CALCULATOR_ADDRESS=${earningPowerCalculaterContractAddress}\nMINT_REWARD_NOTIFIER_ADDRESS=${mintRewardNotifierContractAddress}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
