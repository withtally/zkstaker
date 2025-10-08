import { config as dotEnvConfig } from "dotenv";
import * as zk from 'zksync-ethers';
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, utils } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.

// EarningPowerCalculator deployment constructor arguments
const EARNING_POWER_CALCULATOR_NAME = "BinaryEligibilityOracleEarningPowerCalculator";

// Notifier deployment constructor arguments
const NUMBER_OF_SECONDS_IN_A_DAY = 86400;

// ZkStaker deployment constructor arguments
const ZK_REWARD_TOKEN_ADDRESS = "0xbEBA6afE9851C504e49c7d92BB605003D4cA79Bf";
const ZK_STAKE_TOKEN_ADDRESS = "0xbEBA6afE9851C504e49c7d92BB605003D4cA79Bf";
const MAX_CLAIM_FEE = 500n * (10n ** 18n); // 500 ZK
const STAKER_ADMIN = "0xEAC5F0d4A9a45E1f9FdD0e7e2882e9f60E301156"; // Tally safe
const MAX_BUMP_TIP = 5n * (10n ** 18n); // 5 ZK
const STAKER_NAME = "ZK Staker";
const INITIAL_TOTAL_STAKE_CAP =  400_000_000n * (10n ** 18n); // 400,000,000 ZK
const FEE_AMOUNT = 0;
const FEE_COLLECTOR = "0xf0043eF34F43806318B795b1B671f1EC42DBcd40"
const PROXY_OWNER =  "0xEAC5F0d4A9a45E1f9FdD0e7e2882e9f60E301156" // ZK Token Governor Timelock

// BinaryEligibilityOracle Params
const EARNING_POWER_OWNER = "0xEAC5F0d4A9a45E1f9FdD0e7e2882e9f60E301156";
const SCORE_ORACLE = "0x8120341a040f5776E4a10CC06fB2009fbB187055";
const STALE_ORACLE_WINDOW =  30 * NUMBER_OF_SECONDS_IN_A_DAY;
const ORACLE_PAUSE_GUARDIAN = "0xEAC5F0d4A9a45E1f9FdD0e7e2882e9f60E301156";
const DELEGATEE_SCORE_ELIGIBILITY_THRESHOLD = 1;
const UPDATE_ELIGIBILITY_DELAY = 7 * NUMBER_OF_SECONDS_IN_A_DAY;

async function main() {
  dotEnvConfig();

  // TODO: Uncomment this line referencing the environment variable when secret can be set on CI
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
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
  const earningPowerCalculator = await deployer.deploy(earningPowerCalculatorContractArtifact, [EARNING_POWER_OWNER, SCORE_ORACLE, STALE_ORACLE_WINDOW, ORACLE_PAUSE_GUARDIAN,  DELEGATEE_SCORE_ELIGIBILITY_THRESHOLD, UPDATE_ELIGIBILITY_DELAY], "create", undefined);
  await earningPowerCalculator.deploymentTransaction()?.wait();
  const earningPowerCalculatorContractAddress = await earningPowerCalculator.getAddress();
  console.log(`${earningPowerCalculatorName} was deployed to ${earningPowerCalculatorContractAddress}`);

  // Deploy ZkStaker contract using create
  const zkStakerContractName  = "ZkStaker";
  const zkStakerContractArtifact = await deployer.loadArtifact(zkStakerContractName );
  const constructorArgs = [ZK_REWARD_TOKEN_ADDRESS , ZK_STAKE_TOKEN_ADDRESS, MAX_CLAIM_FEE, zkWallet.address, MAX_BUMP_TIP, earningPowerCalculatorContractAddress, STAKER_NAME, INITIAL_TOTAL_STAKE_CAP];
   const zkStaker = await hre.zkUpgrades.deployProxy(
    deployer.zkWallet,
    zkStakerContractArtifact,
    constructorArgs,
    {
      initializer: "initialize",
      unsafeAllow: ["constructor"],
      initialOwner: PROXY_OWNER
    });
  await zkStaker.deploymentTransaction()?.wait();
  const zkStakerContractAddress = await zkStaker.getAddress();
  console.log(`${zkStakerContractName } was deployed to ${zkStakerContractAddress}`);

  // Set Tally as the claimer
  await zkStaker.setClaimFeeParameters({
    feeAmount: FEE_AMOUNT,
    feeCollector: FEE_COLLECTOR
  });

  // Set the admin of the ZkStaker contract to the timelock
  await zkStaker.setAdmin(STAKER_ADMIN);

  // Output the contract addresses to be captured by the calling script
  console.log(`ZKSTAKER_ADDRESS=${zkStakerContractAddress}\nEARNING_POWER_CALCULATOR_ADDRESS=${earningPowerCalculatorContractAddress}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
