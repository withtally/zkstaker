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
const REWARD_AMOUNT = "1000000000000000000"; // TODO: Verify this value (placeholder for now)
const REWARD_INTERVAL = 30 * NUMBER_OF_SECONDS_IN_A_DAY; // 30 days

// ZkStaker deployment constructor arguments
const ZK_TOKEN_ADDRESS = "0xbEBA6afE9851C504e49c7d92BB605003D4cA79Bf";
const ZK_GOV_OPS_TIMELOCK = "0xDCEE8CAb04Dd58708F7a4d3e8FAE653291f7abeA"
const ZK_CAPPED_MINTER = "0x0066b1DC845874a568B94C592091Ed7e77275A41"; //TODO: Verify this value (placeholder for now)
const MAX_BUMP_TIP = 0;
const INITIAL_TOTAL_STAKE_CAP = "1000000000000000000000000"; // TODO: Verify this value (placeholder for now)
const MAX_CLAIM_FEE = 1000000000000000000n;
const STAKER_NAME = "ZkStaker";

async function main() {
  dotEnvConfig();

  // TODO: Uncomment this line referencing the environment variable when secret can be set on CI
  // const deployerPrivateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
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
  const earningPowerCalculatorContractAddress = await earningPowerCalculator.getAddress();
  console.log(`${earningPowerCalculatorName} was deployed to ${earningPowerCalculatorContractAddress}`);

  // Deploy ZkStaker contract using create
  const zkStakerContractName  = "ZkStaker";
  const zkStakerContractArtifact = await deployer.loadArtifact(zkStakerContractName );
  const constructorArgs = [ZK_TOKEN_ADDRESS, ZK_TOKEN_ADDRESS, MAX_CLAIM_FEE, zkWallet.address, MAX_BUMP_TIP, earningPowerCalculatorContractAddress, STAKER_NAME, INITIAL_TOTAL_STAKE_CAP];
  const zkStaker = await hre.zkUpgrades.deployProxy(
    deployer.zkWallet,
    zkStakerContractArtifact,
    constructorArgs,
    {
      initializer: "initialize",
      unsafeAllow: ["constructor"]
    });
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

  // Set the admin of the ZkStaker contract to the timelock
  await zkStaker.setAdmin(ZK_GOV_OPS_TIMELOCK);

  // Output the contract addresses to be captured by the calling script
  console.log(`ZKSTAKER_ADDRESS=${zkStakerContractAddress}\nEARNING_POWER_CALCULATOR_ADDRESS=${earningPowerCalculatorContractAddress}\nMINT_REWARD_NOTIFIER_ADDRESS=${mintRewardNotifierContractAddress}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
