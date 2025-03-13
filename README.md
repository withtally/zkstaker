# ZkStaker

ZkStaker is built of of Tally's [Staker](https://github.com/withtally/staker) library, and incentivizes delegation within ZK Nation. The current system allows a ZK holder to stake their tokens and earn rewards in ZK tokens. Rewards are currently distributed via minting on a capped minter. In the future other reward sources can be added through a governance vote.

- [Overview](#overview)
- [Setup](#setup)
- [Development](#development)
- [Deployment](#deployment)
- [License](#license)

## Overview

The staking system accepts user stake, delegates their voting power, and distributes rewards for eligible stakers.

```mermaid

stateDiagram-v2
    direction TB

    User --> CUF: Stakes tokens

    state ZkStaker {
        state "Key User Functions" as CUF {
            stake --> claimReward
            claimReward --> withdraw
        }

        state "Key State" as KS {
            rewardRate
            deposits
        }

        state "Admin Functions" as CAF {
            setRewardNotifier
            setEarningPowerCalculator
        }
    }

    state DelegationSurrogate {
        state "Per Delegatee" as PD {
            HoldsTokens
            DelegatesVotes
        }
    }

    KS  --> DelegationSurrogate: Holds tokens per delegatee
    DelegationSurrogate --> Delegatee: Delegates voting power
    "GovOps Governor" --> CAF: admin

    MintRewardNotifier --> ZkStaker: mints capped minter rewards
    IdentityEarningPowerCalculator --> ZkStaker: determines stake rewards


```

## Setup

Before getting started make sure you have Hardhat, Typescript, and [foundry-zksync](https://github.com/matter-labs/foundry-zksync) installed. Once those dependencies are ready follow the steps below.

Clone the repo:

```
git clone https://github.com/withtally/zkstaker.git
cd zk-staker
```

Install the Foundry dependencies:

```
forge install
```

Install the npm dependencies:

```
npm install
```

## Development

Build the contracts, with both `solc` and `zksolc`:

```
npm run compile
```

Run the tests (both the hardhat deployment test and foundry tests are run):

```
npm run test
```

Clean build artifacts, from both `solc` and `zksolc`:

```
npm run clean
```

## Deployment

To deploy the project, you will first need to set up your environment variables via the `.env` file, and potentially change some constant values in the `DeployZkStaker.ts` deployment script.

#### Environment Variables

```bash
cp .env.template .env
# edit the .env to fill in values for DEPLOYER_PRIVATE_KEY and ZKSYNC_RPC_URL
```

The DEPLOYER_PRIVATE_KEY should be the private key of the wallet you want to use for deployment.

The ZKSYNC_RPC_URL should be the RPC URL of the ZkSync network you want to deploy to (e.g., ZkSync Era, ZkSync Testnet, etc.).

#### Script Constants

Before running `DeployZkStaker.ts` verify the below constants are set to the correct values. The current values reflect a mainnet deploy for the ZK Nation GovOps Governor.

```
const REWARD_AMOUNT = "1000000000000000000";
const REWARD_INTERVAL = 30 * NUMBER_OF_SECONDS_IN_A_DAY; // 30 days

const ZK_CAPPED_MINTER = "0x721b6d77a58FaaF540bE49F28D668a46214Ba44c"; // Previously deployed ZK Capped Minter address
const MAX_BUMP_TIP = 0;
const INITIAL_TOTAL_STAKE_CAP = "1000000000000000000000000"; // Limit to the total amount of ZK tokens that can be staked
const STAKER_NAME = "ZkStaker";
```

#### Deployment Execution

For the actual deployment, you will need to use Hardhat and TypeScript. Follow these steps:

Compile the contracts:

```bash
npx hardhat compile
```

For an (optional) local deployment, start a local Hardhat node (in a separate terminal):

```bash
npx hardhat node-zksync
```

This will start a local ZkSync Era node for testing purposes.

Deploy the contracts:

```bash
npx hardhat run script/DeployZkStaker.ts --network <network-name>
```

Make sure to replace `<network-name>` with the desired network (e.g., `zkSyncEra`, `zkSyncLocal`, etc.), which should be defined in your network settings in `hardhat.config.ts`.

For a local deployment, use `zkSyncLocal` as the network-name:

```bash
npx hardhat run script/DeployZkStaker.ts --network zkSyncLocal
```

For a testnet deployment, use `zkSyncEraTestnet` as the network-name:

```bash
npx hardhat run script/DeployZkStaker.ts --network zkSyncEraTestnet
```

For a mainnet deployment, use `zkSyncEra` as the network-name

```bash
npx hardhat run script/DeployZkStaker.ts --network zkSyncEra
```

This will deploy the contracts to the specified network. Make sure you have enough funds in the wallet associated with `DEPLOYER_PRIVATE_KEY` to cover the deployment costs.

If the `--network` flag is not specified, the default network will be used, which is defined in `hardhat.config.ts` as `zkSyncLocal`.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE-MIT) file for details.
