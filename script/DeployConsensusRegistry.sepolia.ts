import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Provider } from "zksync-ethers";
import * as hre from "hardhat";

const ZKSTAKER_ADDRESS = "0x8a2fb7De07d55001FafBe885c2A2Ee00b2cFB484";

// TODO: This ConsensusRegistry deployment file NOT MEANT FOR PRODUCTION PURPOSES.
// It does not use the proxy pattern as intended, and also, initializes in a separate transaction
// (risking hostile takeover on prod). We only wrote this for an e2e sepolia deployment of ZkStaker.
async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const provider = new Provider(process.env.ZKSYNC_RPC_URL);
  const zkWallet = new Wallet(deployerPrivateKey, provider);
  const deployer = new Deployer(hre, zkWallet);

  const consensusRegistryName = "ConsensusRegistry";
  console.log("Deploying " + consensusRegistryName + "...");
  const consensusRegistryArtifact = await deployer.loadArtifact(
    consensusRegistryName
  );
  const constructorArgs: any[] = [];
  const consensusRegistry = await deployer.deploy(
    consensusRegistryArtifact,
    constructorArgs,
    "create",
    undefined
  );

  await consensusRegistry.deploymentTransaction()?.wait();
  const consensusRegistryContractAddress = await consensusRegistry.getAddress();
  console.log(
    `${consensusRegistryName} was deployed to ${consensusRegistryContractAddress}`
  );

  const tx = await consensusRegistry.initialize(ZKSTAKER_ADDRESS);
  await tx.wait();
  console.log(
    "ConsensusRegistry initialized with ZkStaker address: ",
    ZKSTAKER_ADDRESS
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
