# Reward Management Scripts Setup Guide

## Overview

The reward management system uses **two separate scripts** for handling rewards:

1. **RequestMint.ts** - Calculates and requests mints via DelayMod
2. **ExecuteMints.ts** - Finds and executes ready mint requests

This two-script approach works better with delay periods, as it doesn't require long-running processes.

## Quick Start

### 1. Install Dependencies

```bash
npm install --legacy-peer-deps
```

**Note**: We use `--legacy-peer-deps` due to a conflict between hardhat's ethers v6 requirement and Turnkey's ethers v5 requirement.

### 2. Configure Environment Variables

Copy `.env.template` to `.env` and fill in the required values:

```bash
cp .env.template .env
```

Edit `.env` and add:

```bash
# Contract Addresses
ZKSTAKER_ADDRESS="0xYourDeployedZkStakerAddress"
DELAY_MOD_ADDRESS="0xYourDelayModAddress"  # ZkMinterDelayV1 contract
ZK_TOKEN_ADDRESS="0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E"

# RPC Configuration (optional, defaults to zkSync mainnet)
ZKSYNC_RPC_URL="https://sepolia.era.zksync.dev"  # or mainnet

# Turnkey Configuration
TURNKEY_ORGANIZATION_ID="your-org-id-here"
TURNKEY_API_PUBLIC_KEY="your-public-key-here"
TURNKEY_API_PRIVATE_KEY="your-private-key-here"
TURNKEY_WALLET_ADDRESS="0xYourWalletAddress"
```

### 3. Test with Dry Run

```bash
# Test requesting a mint
npm run request-mint -- --rate=3.0 --dry-run

# Test checking for ready mints
npm run execute-mints -- --dry-run
```

This will:
- ✅ Connect to the RPC
- ✅ Fetch current reward state
- ✅ Calculate required rewards (request-mint)
- ✅ Scan for pending requests (execute-mints)
- ✅ Show transaction plan
- ❌ NOT execute any transactions

### 4. Execute Live Workflow

**Step 1: Request a mint**
```bash
npm run request-mint -- --rate=3.0
```

**Step 2: Execute mints after delay period**
```bash
npm run execute-mints
```

## Prerequisites Checklist

Before running the scripts, ensure:

- [ ] Turnkey organization is created
- [ ] Turnkey API keys are generated
- [ ] Turnkey wallet is created and funded (for gas)
- [ ] Turnkey wallet has `MINTER_ROLE` on the DelayMod contract
- [ ] Turnkey wallet has `NOTIFIER_ROLE` on the ZkStaker contract
- [ ] Contract addresses are correctly set in `.env`
- [ ] `.env` file is configured with all Turnkey credentials and contract addresses

## Grant Permissions (Admin Actions)

### Grant Minter Role (Required for RequestMint.ts)

The Turnkey wallet needs the `MINTER_ROLE` on the DelayMod contract:

```solidity
// On ZkMinterDelayV1 (your deployed DelayMod address)
bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
grantRole(MINTER_ROLE, TURNKEY_WALLET_ADDRESS);
```

**Note**: This allows the script to request mints via DelayMod. The mint request creates a time-delayed request that must be executed after the delay period elapses.

### Grant Notifier Role (Required for ExecuteMints.ts)

The Turnkey wallet needs the `NOTIFIER_ROLE` on the ZkStaker contract:

```solidity
// On ZkStaker
bytes32 NOTIFIER_ROLE = keccak256("NOTIFIER_ROLE");
grantRole(NOTIFIER_ROLE, TURNKEY_WALLET_ADDRESS);
```

**Note**: This allows the script to call `notifyRewardAmount()` after mints are executed.

## Usage Examples

### Request a mint to reach 3% APR

```bash
# Dry run first
npm run request-mint -- --rate=3.0 --dry-run

# Execute live
npm run request-mint -- --rate=3.0
```

### Execute pending mints

```bash
# Check what's ready (dry run)
npm run execute-mints -- --dry-run

# Execute all ready mints
npm run execute-mints
```

### Manually notify rewards (recovery/standalone use)

Only needed if the `execute-mints` script executes a mint, but fails to notify staker.

```bash
# Dry run first
npm run notify-reward -- --amount=100000000000000000 --dry-run

# Execute live
npm run notify-reward -- --amount=100000000000000000
```

**Note**: Amount should be in wei (1 ZK = 1000000000000000000 wei)

### Complete workflow example

```bash
# Step 1: Request mint for 5.5% APR
npm run request-mint -- --rate=5.5

# Output shows: Can execute after 2025-11-04T10:30:00.000Z

# Step 2: Wait for delay period to elapse

# Step 3: Execute the ready mint
npm run execute-mints
```

## Troubleshooting

### "Missing Turnkey configuration" or "ZKSTAKER_ADDRESS is not set"

- Verify all environment variables are set in `.env`
- Check for typos or extra spaces
- Ensure the `.env` file is in the project root
- Make sure contract addresses are set (ZKSTAKER_ADDRESS, DELAY_MOD_ADDRESS, ZK_TOKEN_ADDRESS)

### "Missing role" errors when requesting mints

**Error**: `AccessControl: account ... is missing role ...`

**Solution**: Grant `MINTER_ROLE` to your Turnkey wallet on the DelayMod contract:
```solidity
delayMod.grantRole(MINTER_ROLE, TURNKEY_WALLET_ADDRESS);
```

### "not notifier" error when executing mints

**Error**: Execution fails with "not notifier" message

**Solution**: Grant `NOTIFIER_ROLE` to your Turnkey wallet on the ZkStaker contract:
```solidity
staker.grantRole(NOTIFIER_ROLE, TURNKEY_WALLET_ADDRESS);
```

### "No ready mint requests found"

- All pending requests are still in their delay period
- Check the "Can execute after" timestamp from the RequestMint output
- Run `npm run execute-mints -- --dry-run` to see pending requests and wait times

### "No action needed" when requesting mint

- The current reward rate is already at or above the desired rate
- Wait for the current reward period to progress
- Use a higher `--rate` value if you want to increase the rate

### Mint executed but notify failed

If ExecuteMints shows "CRITICAL: Mint executed but notify failed":
1. Grant `NOTIFIER_ROLE` to your Turnkey wallet (see above)
2. Run the NotifyReward script manually:
   ```bash
   npm run notify-reward -- --amount=<amount_from_error_message>
   ```

### Dependency Installation Issues

If you encounter issues during `npm install`, try:

```bash
rm -rf node_modules package-lock.json
npm install --legacy-peer-deps
```

## Documentation

For detailed documentation, see:
- `script/rewards/README_TWO_SCRIPT_WORKFLOW.md` - Complete two-script workflow guide
- `script/rewards/DELAYMOD_MIGRATION.md` - DelayMod migration guide
- `script/rewards/RequestMint.ts` - Request mint source code
- `script/rewards/ExecuteMints.ts` - Execute mints source code
- `script/rewards/NotifyReward.ts` - Manual notify source code

## Available Scripts

The reward management system includes these npm scripts:

- `npm run request-mint -- --rate=<percentage> [--dry-run]` - Request a mint to reach desired APR
- `npm run execute-mints [--dry-run]` - Execute all ready mint requests
- `npm run notify-reward -- --amount=<wei> [--dry-run]` - Manually notify rewards (recovery tool)

## Security Notes

- Never commit your `.env` file
- Keep Turnkey API keys secure
- Always test with `--dry-run` first
- Monitor transactions on a block explorer
- Be cautious with reward rates - they have economic implications
- The ExecuteMints script can be run by anyone (no special permissions needed for execution)
- Only RequestMint requires `MINTER_ROLE` on DelayMod
- Only NotifyReward/ExecuteMints require `NOTIFIER_ROLE` on ZkStaker

## Support

For issues or questions:
- Review the full documentation in `README_TWO_SCRIPT_WORKFLOW.md`
- Check Turnkey documentation at https://docs.turnkey.com
- Check DelayMod documentation at https://docs.zknation.io
- Verify contract permissions and role assignments
