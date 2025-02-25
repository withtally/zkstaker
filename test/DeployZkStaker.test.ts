import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { execSync, spawn } from "child_process";
import * as dotenv from "dotenv";

dotenv.config();

describe("DeployZkStaker", function () {
  let zkStaker: Contract;
  let localNodeProcess: any;
  let contractAddress = ""
  let earningPowerCalculatorAddress = "";

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
      const output = execSync("npm run script DeployZkStaker.ts", { encoding: "utf-8" });
      console.log("Deploy script output:", output);
      const zkStakerMatch = output.match(/ZKSTAKER_ADDRESS=(0x[a-fA-F0-9]{40})\n/);
      const earningPowerCalculatorMatch = output.match(/EARNING_POWER_CALCULATOR_ADDRESS=(0x[a-fA-F0-9]{40})\n/);
      if (zkStakerMatch) {
        contractAddress = zkStakerMatch[1];
        console.log(`Deployed contract address: ${contractAddress}`);
      } else {
        console.error("Failed to capture the ZkStaker contract address.");
      }
      if (earningPowerCalculatorMatch) {
        earningPowerCalculatorAddress = earningPowerCalculatorMatch[1];
        console.log(`Deployed earning power calculator address: ${earningPowerCalculatorAddress}`);
      } else {
        console.error("Failed to capture the earning power calculator contract address.");
      }
    } catch (error) {
      console.error("Error deploying contract:", error);
    }
    // Get the deployed contract instance
    const ZkStaker = await ethers.getContractFactory("ZkStaker");
    zkStaker = ZkStaker.attach(contractAddress) as Contract;
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
    const ZK_TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
    const MAX_CLAIM_FEE = 1000000000000000000n;
    const MAX_BUMP_TIP = 100000000000000000000000n;
    const ZK_TOKEN_TIMELOCK_ADDRESS = "0x3E21c654B545Bf6236DC08236169DcF13dA4dDd6"; // TDDO: Verify this address

    expect(await zkStaker.REWARD_TOKEN()).to.equal(ZK_TOKEN_ADDRESS);
    expect(await zkStaker.STAKE_TOKEN()).to.equal(ZK_TOKEN_ADDRESS);
    expect(await zkStaker.MAX_CLAIM_FEE()).to.equal(MAX_CLAIM_FEE);
    expect(await zkStaker.maxBumpTip()).to.equal(MAX_BUMP_TIP);
    expect(await zkStaker.earningPowerCalculator()).to.equal(earningPowerCalculatorAddress);
    expect(await zkStaker.admin()).to.equal(ZK_TOKEN_TIMELOCK_ADDRESS);
  });
});