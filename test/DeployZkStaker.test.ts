import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { execSync, spawn } from "child_process";
import * as dotenv from "dotenv";

dotenv.config();

describe("DeployZkStaker", function () {
  let zkStaker: Contract;
  let mintRewardNotifier: Contract;
  let earningPowerCalculator: Contract;
  let localNodeProcess: any;
  let zkStakerContractAddress  = ""
  let earningPowerCalculatorAddress = "";
  let mintRewardNotifierAddress = "";

  before(async function () {
    // Get the local Hardhat node is running
    try {
      console.log("Starting local Hardhat node...");
      localNodeProcess = spawn("npm", ["run", "local-node"], {
        stdio: "ignore",
        detached: true
      });
      console.log("Local Hardhat node started.");
    } catch (error) {
      console.error("Hardhat local node did not start.");
      process.exit(1);
    }

    // Wait for a few seconds to ensure the local node is ready
    await new Promise((resolve) => setTimeout(resolve, 3000));

    console.log("About to run deploy script...");
    // Run the deploy script
    try {
      const output = execSync("npm run script DeployZkStaker.ts zkSyncLocal", { encoding: "utf-8" });
      console.log("Deploy script output:", output);
      const zkStakerMatch = output.match(/ZKSTAKER_ADDRESS=(0x[a-fA-F0-9]{40})\n/);
      const earningPowerCalculatorMatch = output.match(/EARNING_POWER_CALCULATOR_ADDRESS=(0x[a-fA-F0-9]{40})\n/);
      const mintRewardNotifierMatch = output.match(/MINT_REWARD_NOTIFIER_ADDRESS=(0x[a-fA-F0-9]{40})\n/);
      if (zkStakerMatch) {
        zkStakerContractAddress  = zkStakerMatch[1];
        console.log(`Deployed ZkStaker contract address: ${zkStakerContractAddress }`);
      } else {
        console.error("Failed to capture the ZkStaker contract address.");
      }
      if (earningPowerCalculatorMatch) {
        earningPowerCalculatorAddress = earningPowerCalculatorMatch[1];
        console.log(`Deployed earning power calculator address: ${earningPowerCalculatorAddress}`);
      } else {
        console.error("Failed to capture the earning power calculator contract address.");
      }
      if (mintRewardNotifierMatch) {
        mintRewardNotifierAddress = mintRewardNotifierMatch[1];
        console.log(`Deployed mint reward notifier address: ${mintRewardNotifierAddress}`);
      } else {
        console.error("Failed to capture the mint reward notifier contract address.");
      }

    } catch (error) {
      console.error("Error deploying contract:", error);
    }
    // Get the deployed contract instances
    const ZkStaker = await ethers.getContractFactory("ZkStaker");
    const BinaryEligibilityOracleEarningPowerCalculator = await ethers.getContractFactory("BinaryEligibilityOracleEarningPowerCalculator");
    zkStaker = ZkStaker.attach(zkStakerContractAddress ) as Contract;
    earningPowerCalculator  = BinaryEligibilityOracleEarningPowerCalculator.attach(earningPowerCalculatorAddress) as Contract;
  });

  after(async function () {
    // Terminate the local Hardhat node process
    if (localNodeProcess) {
      process.kill(-localNodeProcess.pid);
    }
  });

  it("should deploy the ZkStaker contract", async function () {
    expect(await zkStaker.getAddress()).to.properAddress;
  });

  it("should deploy the EarningPowerCalculator contract", async function () {
    expect(await zkStaker.earningPowerCalculator()).to.properAddress;
  });

  it("should have the correct constructor arguments", async function () {
		const raw = await hre.zk.provider.getStorageAt(zkStakerContractAddress, "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103");
		const proxyAdminAddress = ethers.getAddress("0x" + raw.slice(26));
		const ProxyAdminContract = await hre.zk.getContractAt("ProxyAdmin", proxyAdminAddress);

    const ZK_TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
    const MAX_CLAIM_FEE = 500n * (10n ** 18n);
    const MAX_BUMP_TIP = 0;
    const INITIAL_TOTAL_STAKE_CAP = 400_000_000n * (10n ** 18n);
    const STAKER_ADMIN = "0xf0043eF34F43806318B795b1B671f1EC42DBcd40"; // Tally safe
		const PROXY_ADMIN_OWNER = await ProxyAdminContract.owner();
		const TOKEN_GOVERNOR_TIMELOCK = "0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d";


    expect(await zkStaker.REWARD_TOKEN()).to.equal(ZK_TOKEN_ADDRESS);
    expect(await zkStaker.STAKE_TOKEN()).to.equal(ZK_TOKEN_ADDRESS);
    expect(await zkStaker.MAX_CLAIM_FEE()).to.equal(MAX_CLAIM_FEE);
    expect(await zkStaker.maxBumpTip()).to.equal(MAX_BUMP_TIP);
    expect(await zkStaker.totalStakeCap()).to.equal(INITIAL_TOTAL_STAKE_CAP);
    expect(await zkStaker.earningPowerCalculator()).to.equal(earningPowerCalculatorAddress);
    expect(await zkStaker.admin()).to.equal(STAKER_ADMIN);
    expect(PROXY_ADMIN_OWNER).to.equal(TOKEN_GOVERNOR_TIMELOCK);
  });
});
