import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-node";
import "@matterlabs/hardhat-zksync-upgradable";
import "@matterlabs/hardhat-zksync-verify";


import * as dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  zksolc: {
    version: "1.5.11",
    settings: {
      optimizer: {
        enabled: true,
      },
    },
  },
  paths: {
    "sources": "./src",
  },
  networks: {
    hardhat: {
      zksync: false,
    },
    ethNetwork: {
      zksync: false,
      url: "http://localhost:8545",
    },
		zkSyncLocal: {
      zksync: true,
      ethNetwork: "ethNetwork",
      url: "http://0.0.0.0:8011",
    },
    zkSyncEra: {
      zksync: true,
      ethNetwork: "mainnet",
      url: process.env.ZKSYNC_MAINNET_RPC_URL || "https://mainnet.era.zksync.io",
			verifyURL: "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
    zkSyncTestnet: {
      zksync: true,
      ethNetwork: "sepolia",
      url: "https://sepolia.era.zksync.dev"
    },
  },
  defaultNetwork: "zkSyncLocal",
};

export default config;
