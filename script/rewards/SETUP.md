# RewardNotifier Script Setup Guide

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

# Turnkey Configuration
TURNKEY_ORGANIZATION_ID="your-org-id-here"
TURNKEY_API_PUBLIC_KEY="your-public-key-here"
TURNKEY_API_PRIVATE_KEY="your-private-key-here"
TURNKEY_WALLET_ADDRESS="0xYourWalletAddress"
```

### 3. Run a Dry Run Test

```bash
npm run reward-notifier -- --rate=3.0 --dry-run
```

This will:
- ✅ Connect to the RPC
- ✅ Fetch current reward state
- ✅ Calculate required rewards
- ✅ Show transaction plan
- ❌ NOT execute any transactions

### 4. Execute Live (when ready)

```bash
npm run reward-notifier -- --rate=3.0
```

## Prerequisites Checklist

Before running the script, ensure:

- [ ] Turnkey organization is created
- [ ] Turnkey API keys are generated
- [ ] Turnkey wallet is created and funded (for gas)
- [ ] Turnkey wallet has `MINTER_ROLE` on the DelayMod contract
- [ ] Turnkey wallet is authorized as a notifier on ZkStaker
- [ ] Contract addresses are correctly set in `.env`
- [ ] `.env` file is configured with all Turnkey credentials and contract addresses

## Grant Permissions (Admin Actions)

### Grant Minter Role

The Turnkey wallet needs the `MINTER_ROLE` on the DelayMod contract:

```solidity
// On ZkMinterDelayV1 (your deployed DelayMod address)
grantRole(MINTER_ROLE, TURNKEY_WALLET_ADDRESS);
```

**Note**: The script uses a DelayMod which creates a time-delayed mint request. The mint must be executed after the delay period elapses.

### Authorize as Reward Notifier

The Turnkey wallet needs to be authorized on the ZkStaker contract:

```solidity
// On ZkStaker
setRewardNotifier(TURNKEY_WALLET_ADDRESS, true);
```

## Usage Examples

### Check if rewards need to be added (dry run)

```bash
npm run reward-notifier -- --rate=3.0 --dry-run
```

### Add rewards to reach 3% APR

```bash
npm run reward-notifier -- --rate=3.0
```

### Add rewards to reach 5.5% APR

```bash
npm run reward-notifier -- --rate=5.5
```

## Troubleshooting

### "Missing Turnkey configuration" or "ZKSTAKER_ADDRESS is not set"

- Verify all environment variables are set in `.env`
- Check for typos or extra spaces
- Ensure the `.env` file is in the project root
- Make sure contract addresses are set (ZKSTAKER_ADDRESS, DELAY_MOD_ADDRESS, ZK_TOKEN_ADDRESS)

### "Mint transaction failed"

- Verify the wallet has `MINTER_ROLE`
- Check if the minter contract is paused or closed
- Verify the minting cap hasn't been reached

### "No action needed"

- The current reward rate is already at or above the desired rate
- Wait for the current reward period to progress
- Use a higher `--rate` value if you want to increase the rate

### Dependency Installation Issues

If you encounter issues during `npm install`, try:

```bash
rm -rf node_modules package-lock.json
npm install --legacy-peer-deps
```

## Documentation

For detailed documentation, see:
- `script/README_REWARD_NOTIFIER.md` - Complete documentation
- `script/RewardNotifier.ts` - Source code with inline comments

## Security Notes

- Never commit your `.env` file
- Keep Turnkey API keys secure
- Always test with `--dry-run` first
- Monitor transactions on a block explorer
- Be cautious with reward rates - they have economic implications

## Support

For issues or questions:
- Review the full documentation in `README_REWARD_NOTIFIER.md`
- Check Turnkey documentation at https://docs.turnkey.com
- Verify contract permissions and authorization
