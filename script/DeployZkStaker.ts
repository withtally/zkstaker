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
const REWARD_AMOUNT = "1000000000000000000"; // 1e18 string instead of bigNumber
const NUMBER_OF_SECONDS_IN_A_DAY = 86400;
const REWARD_INTERVAL = 30 * NUMBER_OF_SECONDS_IN_A_DAY; // 30 days


// ZkStaker deployment constructor arguments
const ZK_TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const ZK_TOKEN_TIMELOCK_ADDRESS = "0x3E21c654B545Bf6236DC08236169DcF13dA4dDd6"; // TDDO: Verify this address
const MAX_BUMP_TIP = "1000000000000000000"; // 1e18 string instead of bigNumber
const INITIAL_TOTAL_STAKE_CAP = "1000000000000000000000000"; // 1e24 string instead of bigNumber
const STAKER_NAME = "ZkStaker";


async function main() {
  dotEnvConfig();

  // TODO: Uncomment this line referencing the environment variable when secret can be set on CI
  const deployerPrivateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  // const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
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
  earningPowerCalculator.deploymentTransaction()?.wait();
  const earningPowerCalculaterContractAddress = await earningPowerCalculator.getAddress();
  console.log(`${earningPowerCalculatorName} was deployed to ${earningPowerCalculaterContractAddress}`);

  // Deploy ZkStaker contract using create
  const zkStakerContractName  = "ZkStaker";
  const zkStakerContractArtifact = await deployer.loadArtifact(zkStakerContractName );
  const constructorArgs = [ZK_TOKEN_ADDRESS, ZK_TOKEN_ADDRESS, earningPowerCalculaterContractAddress, MAX_BUMP_TIP, INITIAL_TOTAL_STAKE_CAP, zkWallet.address, STAKER_NAME];
  const zkStaker = await deployer.deploy(zkStakerContractArtifact, constructorArgs, "create", undefined);
  zkStaker.deploymentTransaction()?.wait();
  const zkStakerContractAddress = await zkStaker.getAddress();
  console.log(`${zkStakerContractName } was deployed to ${zkStakerContractAddress}`);

  // Deploy the MintRewardNotifier contract using create
  const mintRewardNotifierContractName = "MintRewardNotifier";
  const mintRewardNotifierContractArtifact = await deployer.loadArtifact(mintRewardNotifierContractName);
  const mintRewardNotifier = await deployer.deploy(mintRewardNotifierContractArtifact, [zkStakerContractAddress, REWARD_AMOUNT, REWARD_INTERVAL, ZK_TOKEN_TIMELOCK_ADDRESS, ZK_TOKEN_TIMELOCK_ADDRESS], "create", undefined);
  mintRewardNotifier.deploymentTransaction()?.wait();
  const mintRewardNotifierContractAddress = await mintRewardNotifier.getAddress();
  console.log(`${mintRewardNotifierContractName} was deployed to ${mintRewardNotifierContractAddress}`);

  // Set the notifier of the ZkStaker contract to the MintRewardNotifier
  await zkStaker.setRewardNotifier(mintRewardNotifierContractAddress, true);

  // Set the admin of the ZkStaker contract to the timelock
  await zkStaker.setAdmin(ZK_TOKEN_TIMELOCK_ADDRESS);

  // Output the contract addresses to be captured by the calling script
  console.log(`ZKSTAKER_ADDRESS=${zkStakerContractAddress}\nEARNING_POWER_CALCULATOR_ADDRESS=${earningPowerCalculaterContractAddress}\nMINT_REWARD_NOTIFIER_ADDRESS=${mintRewardNotifierContractAddress}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
