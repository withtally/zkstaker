# ZKStaker Reward Notifier Script

## Overview

The `RewardNotifier.ts` script automates the process of adding rewards to the ZKStaker system. It implements the RewardNotifier pattern using an EOA (Externally Owned Account) controlled by Turnkey for secure key management.

## How It Works

### Background

The ZKStaker contract uses a continuous reward distribution mechanism:
- Rewards are distributed over a 30-day period (`REWARD_DURATION`)
- The reward rate is calculated as: `rewardRate = totalRewards / REWARD_DURATION`
- Stakers earn rewards proportional to their earning power (staked amount)

### Script Logic

1. **Fetch Current State**: Queries the ZKStaker contract for:
   - Current scaled reward rate
   - Reward end time
   - Total earning power (total staked amount)

2. **Calculate Required Rewards**:
   - Converts the current reward rate to an annual percentage (APR)
   - Compares it with the desired rate (provided as a parameter)
   - If current rate ≥ desired rate: exits (no action needed)
   - If current rate < desired rate: calculates how many tokens need to be added

3. **Create Transaction Plan**:
   - **Transaction 1**: Mint rewards via `ZkCappedMinterV2.mint()`
   - **Transaction 2**: Notify staker via `ZkStaker.notifyRewardAmount()`

4. **Execute Transactions** (if not in dry-run mode):
   - Signs transactions using Turnkey's secure key management
   - Executes transactions sequentially
   - Handles partial failures with clear instructions

## Prerequisites

### 1. Turnkey Setup

You need a Turnkey account with:
- An organization created
- An API key pair generated
- A wallet/account created with the `MINTER_ROLE` on the `ZkCappedMinterV2` contract
- The wallet must be authorized as a reward notifier on the ZKStaker contract

To set up Turnkey:
1. Visit [https://app.turnkey.com](https://app.turnkey.com)
2. Create an organization
3. Generate an API key pair (save both public and private keys)
4. Create a wallet/account
5. Get the wallet address

### 2. Contract Permissions

The Turnkey-controlled wallet must have:
- `MINTER_ROLE` on the `ZkCappedMinterV2` contract at `0x721b6d77a58FaaF540bE49F28D668a46214Ba44c`
- Authorization as a reward notifier on the ZKStaker contract

### 3. Environment Configuration

Copy `.env.template` to `.env` and fill in:

```bash
# RPC URL for zkSync Era
ZKSYNC_RPC_URL=https://mainnet.era.zksync.io

# Contract Addresses
ZKSTAKER_ADDRESS="0x..."  # Your deployed ZkStaker address
ZKCAPPED_MINTER_ADDRESS="0x721b6d77a58FaaF540bE49F28D668a46214Ba44c"
ZK_TOKEN_ADDRESS="0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E"

# Turnkey Configuration
TURNKEY_ORGANIZATION_ID="your-organization-id"
TURNKEY_API_PUBLIC_KEY="your-api-public-key"
TURNKEY_API_PRIVATE_KEY="your-api-private-key"
TURNKEY_WALLET_ADDRESS="0x..."  # Your Turnkey wallet address
```

## Installation

Install dependencies:

```bash
npm install
```

This will install:
- `ethers` - Ethereum interaction library
- `@turnkey/ethers` - Turnkey integration for Ethers.js
- `@turnkey/http` - Turnkey HTTP client
- `@turnkey/api-key-stamper` - API key authentication for Turnkey

## Usage

### Dry Run Mode (Recommended First)

Test the script without executing transactions:

```bash
npm run script script/RewardNotifier.ts -- --rate=3.0 --dry-run
```

This will:
- ✅ Fetch current reward state
- ✅ Calculate required rewards
- ✅ Show transaction plan
- ❌ NOT execute any transactions
- ❌ NOT sign with Turnkey

### Live Execution

Execute the transactions:

```bash
npm run script script/RewardNotifier.ts -- --rate=3.0
```

This will:
- ✅ Fetch current reward state
- ✅ Calculate required rewards
- ✅ Initialize Turnkey signer
- ✅ Execute mint transaction
- ✅ Execute notify transaction
- ✅ Verify new state

## Parameters

### `--rate=<percentage>` (Required)

The desired annual percentage rate (APR) for rewards.

Examples:
- `--rate=3.0` → 3% APR
- `--rate=5.5` → 5.5% APR
- `--rate=10` → 10% APR

### `--dry-run` (Optional)

Run in dry-run mode (no transactions executed).

## Example Output

### Dry Run Example

```
🎯 ZKStaker Reward Notifier
======================================================================
Mode: DRY RUN
Desired Rate: 3.0% APR
ZKStaker: 0x1234...5678
Minter: 0x721b...44c
======================================================================

🔍 Fetching current reward state...

📊 Current Reward State:
   Current Rate: 2.1234% APR
   Desired Rate: 3.0000% APR
   Total Earning Power: 1000000.0 ZK
   Reward End Time: 2025-11-28T10:00:00.000Z

📋 Transaction Plan:
   Rewards to Add: 7200.0 ZK
   New Rate: 3.0123% APR

======================================================================
🔍 DRY RUN MODE
======================================================================

📝 Transaction 1: Mint Rewards
   Contract: 0x721b6d77a58FaaF540bE49F28D668a46214Ba44c
   Function: mint(address to, uint256 amount)
   To: 0x1234...5678
   Amount: 7200.0 ZK
   Status: ⏭️  Skipped (dry run)

📝 Transaction 2: Notify Staker
   Contract: 0x1234...5678
   Function: notifyRewardAmount(uint256 amount)
   Amount: 7200.0 ZK
   Status: ⏭️  Skipped (dry run)

======================================================================
✅ Dry run completed successfully
======================================================================

👋 Exiting - no action required
```

### No Action Needed Example

```
📊 Current Reward State:
   Current Rate: 3.5000% APR
   Desired Rate: 3.0000% APR
   Total Earning Power: 1000000.0 ZK
   Reward End Time: 2025-11-28T10:00:00.000Z

✅ Current rate (3.5000%) is already at or above desired rate (3.0000%)
   No action needed.

👋 Exiting - no action required
```

## Error Handling

### Partial Failure Scenario

The script is designed to handle the most critical failure scenario: when the mint succeeds but the notify fails.

If this happens, you'll see:

```
======================================================================
⚠️  CRITICAL STATE: MANUAL INTERVENTION REQUIRED ⚠️
======================================================================

The mint transaction SUCCEEDED but the notify transaction FAILED.
The staker contract is now in a BAD STATE:

  - 7200.0 ZK tokens have been minted to the staker
  - The staker has NOT been notified of these rewards
  - The reward rate has NOT been updated

TO FIX THIS STATE:

1. Verify the minted tokens are in the staker contract:
   Check balance at: 0x1234...5678

2. Call notifyRewardAmount manually with the correct amount:
   Contract: 0x1234...5678
   Function: notifyRewardAmount(uint256 7200000000000000000000)
   Amount: 7200000000000000000000 (7200.0 ZK)

3. After successful notification, verify the new reward rate.

DO NOT run this script again until the state is fixed!
======================================================================
```

**Important**: If you see this error:
1. ❌ DO NOT run the script again
2. ✅ Follow the manual recovery instructions
3. ✅ Verify the state is fixed before running again

### Other Errors

- **Missing Turnkey Configuration**: Check your `.env` file
- **Insufficient Permissions**: Ensure the wallet has `MINTER_ROLE` and notifier authorization
- **Insufficient Minting Cap**: The minter may have reached its cap
- **RPC Connection Issues**: Check your `ZKSYNC_RPC_URL`

## Architecture Details

### Contract Interactions

```
┌─────────────────┐
│ RewardNotifier  │
│    (Script)     │
└────────┬────────┘
         │
         ├──────────────────┐
         │                  │
         ▼                  ▼
┌──────────────────┐  ┌──────────────┐
│ ZkCappedMinterV2 │  │  ZkStaker    │
│                  │  │              │
│ mint(to, amt)    │  │ notifyReward │
│                  │  │   Amount()   │
└──────────────────┘  └──────────────┘
         │                  │
         └────────┬─────────┘
                  ▼
         ┌─────────────────┐
         │    ZK Token     │
         │   (ERC20)       │
         └─────────────────┘
```

### Reward Rate Calculation

The script uses the following formula to calculate the current APR:

```
annualRewards = scaledRewardRate × secondsPerYear
ratePercentage = (annualRewards / totalEarningPower / SCALE_FACTOR) × 100
```

Where:
- `scaledRewardRate` = Current rate from the staker contract (scaled by 10^18)
- `secondsPerYear` = 365 × 24 × 60 × 60 = 31,536,000
- `totalEarningPower` = Total staked amount (earning power)
- `SCALE_FACTOR` = 10^18

To reach a desired rate, the script calculates:

```
desiredAnnualRewards = totalEarningPower × desiredRate / 100
desiredScaledRate = (desiredAnnualRewards × SCALE_FACTOR) / secondsPerYear
rewardsToAdd = (desiredScaledRate × REWARD_DURATION / SCALE_FACTOR) - remainingRewards
```

## Security Considerations

1. **Key Management**:
   - Never commit your `.env` file
   - Keep Turnkey API keys secure
   - Use Turnkey's policy engine to restrict the wallet's capabilities

2. **Authorization**:
   - Only authorized addresses should have the ability to mint and notify
   - The script will fail if permissions are not correctly set

3. **Rate Limits**:
   - Be cautious with very high reward rates
   - The minter has a cap that cannot be exceeded
   - Consider the economic implications of reward rates

4. **Dry Run First**:
   - Always test with `--dry-run` before executing
   - Verify the transaction plan makes sense
   - Check that the calculated amounts are correct

## Troubleshooting

### Script fails with "Missing Turnkey configuration" or "ZKSTAKER_ADDRESS is not set"

- Check that all environment variables are set in `.env`:
  - Contract addresses: `ZKSTAKER_ADDRESS`, `ZKCAPPED_MINTER_ADDRESS`, `ZK_TOKEN_ADDRESS`
  - Turnkey credentials: `TURNKEY_ORGANIZATION_ID`, `TURNKEY_API_PUBLIC_KEY`, `TURNKEY_API_PRIVATE_KEY`, `TURNKEY_WALLET_ADDRESS`
- Verify the values are correct (no extra quotes or whitespace)
- Ensure the `.env` file is in the project root directory

### Script fails with "Mint transaction failed"

- Verify the wallet has `MINTER_ROLE` on the minter contract
- Check if the minter has reached its cap
- Ensure the minter contract is not paused or closed

### Script fails with "Notify transaction failed" (but mint succeeded)

- Follow the manual recovery instructions in the error message
- DO NOT run the script again until recovered

### Script shows "No action needed" but you expected it to mint

- Check that your desired rate is higher than the current rate
- The current rate may have increased since you last checked
- Verify the `totalEarningPower` is non-zero (someone must have staked)

## References

- [Staker Contract](https://github.com/withtally/staker/blob/v1.0.1/src/Staker.sol)
- [RewardTokenNotifierBase](https://github.com/withtally/staker/blob/main/src/notifiers/RewardTokenNotifierBase.sol)
- [MintRewardNotifier](https://github.com/withtally/staker/blob/main/src/notifiers/MintRewardNotifier.sol)
- [ZkCappedMinterV2](https://github.com/ScopeLift/zk-governance/blob/master/l2-contracts/src/ZkCappedMinterV2.sol)
- [Turnkey Documentation](https://docs.turnkey.com)
- [Turnkey Ethereum Support](https://docs.turnkey.com/networks/ethereum)
