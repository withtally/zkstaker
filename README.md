# ZkStaker

ZkStaker is a flexible, configurable staking contract. ZkStaker makes it easy to distribute onchain staking rewards for any ERC20 token on the ZkSync Era, including ZK Nation DAO governance tokens. It is based on the Staker contracts. For more information, visit the [Staker Documentation](https://example.com/staker-docs).

## Deployment

To deploy the project, you will need to use Hardhat and TypeScript. Follow these steps:

1. Install dependencies:

   ```bash
   npm install
   ```

2. Compile the contracts:

   ```bash
   npx hardhat compile
   ```

3. For an (optional) local deployment, start a local Hardhat node:

   ```bash
   npx hardhat node-zksync
   ```

   This will start a local ZkSync Era node for testing purposes.

4. Deploy the contracts:
   ```bash
   npx hardhat run script/DeployZkStaker.ts --network <network-name>
   ```

Make sure to replace `<network-name>` with the desired network (e.g., `mainnet`, `ropsten`, etc.). You will also need to configure your network settings in `hardhat.config.ts`.

### Development

These contracts were built and tested with care by the team at [ScopeLift](https://scopelift.co).

#### Requirements

This repository uses the [Foundry](https://book.getfoundry.sh/) development framework for testing. Install Foundry using these [instructions](https://book.getfoundry.sh/getting-started/installation).

This repository also uses the [Hardhat](https://hardhat.org/docs) development framework, with the relevant [zkSync Era plugins](https://docs.zksync.io/build/tooling/hardhat/getting-started.html) for managing deployments.

We use [Volta](https://docs.volta.sh/guide/) to ensure a consistent npm environment between developers. Install volta using these [instructions](https://docs.volta.sh/guide/getting-started).

#### Setup

Clone the repo:

```
git clone https://github.com/withtally/zkstaker.git
cd zk-staker
```

Install the npm dependencies:

```
npm install
```

Install the Foundry dependencies:

```
forge install
```

Set up your `.env` file:

```bash
cp .env.template .env
# edit the .env to fill in values
```

#### Build and Test

Build the contracts, with both `solc` and `zksolc`:

```
npm run compile
```

Run the tests (both the hardhat deployment test and foundry tests are run):):

```
npm run test
```

Clean build artifacts, from both `solc` and `zksolc`:

```
npm run clean
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
