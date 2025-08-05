import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Provider, Contract } from "zksync-ethers";
import * as hre from "hardhat";

const ZK_STAKER_CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000";
const INTENDED_ADMIN = "0xC3e970cB015B5FC36edDf293D2370ef5D00F7a19";

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const provider = new Provider(process.env.ZKSYNC_RPC_URL);
  const zkWallet = new Wallet(deployerPrivateKey, provider);
  const deployer = new Deployer(hre, zkWallet);

  const zkStaker = new Contract(
    ZK_STAKER_CONTRACT_ADDRESS,
    await deployer.loadArtifact("ZkStaker").then((val) => val.abi),
    zkWallet
  );

  console.log(
    `Setting admin of ${ZK_STAKER_CONTRACT_ADDRESS} to ${INTENDED_ADMIN}`
  );
  await zkStaker.setAdmin(INTENDED_ADMIN);
  console.log(`Admin set to ${INTENDED_ADMIN}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
