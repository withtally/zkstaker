import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Provider, Contract } from "zksync-ethers";
import * as hre from "hardhat";

const ZK_STAKER_CONTRACT_ADDRESS = "0x8a2fb7De07d55001FafBe885c2A2Ee00b2cFB484";
const CONSENSUS_REGISTRY = "0x158d33FbddA2263FE08d8f4955f13cd9F20B4c05";

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

  // Set the consensus registry of the ZkStaker contract
  await zkStaker.setRegistry(CONSENSUS_REGISTRY);
  console.log(`Registry set to ${CONSENSUS_REGISTRY}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
