# Reward Management Scripts

## Overview

The reward management system uses **two separate scripts** to handle the delayed minting process via ZkMinterDelayV1 (DelayMod), plus a **disaster recovery script**:

1. **RequestMint.ts** - Calculates required rewards and requests a mint
2. **ExecuteMints.ts** - Finds ready mint requests and executes them
3. **NotifyReward.ts** - Disaster recovery: manually notify staker of rewards

This separation allows for flexible operation with any delay period, as the execution script doesn't need to wait.

## Why Two Scripts?

The DelayMod introduces a time delay (veto window) between requesting and executing mints. Rather than having a single script wait for hours or days, we split the workflow:

- **Request**: Quick operation, calculates and submits mint request
- **Execute**: Stateless scanner that finds and executes ready requests

This design:
- ✅ Works with any delay period (minutes to days)
- ✅ No need to keep a script running
- ✅ Can be run by anyone after delay period
- ✅ Handles multiple pending requests automatically
- ✅ Easy to schedule via cron or CI/CD

## Quick Start

### Step 1: Request a Mint

```bash
# Dry run to see what would happen
npm run request-mint -- --rate=3.0 --dry-run

# Actually request the mint
npm run request-mint -- --rate=3.0
```

**Output:**
```
✅ MINT REQUEST CREATED SUCCESSFULLY
   Request ID: 5
   Amount: 8.5 ZK
   Can execute after: 2025-11-04T10:30:00.000Z

📝 Next Steps:
   1. Wait until 2025-11-04T10:30:00.000Z
   2. Run: npx ts-node --transpileOnly script/rewards/ExecuteMints.ts
```

### Step 2: Execute Ready Mints

After the delay period:

```bash
# Dry run to see what would execute
npm run execute-mints -- --dry-run

# Execute all ready mints
npm run execute-mints
```

**Output:**
```
🔍 Scanning for pending mint requests...
   ✅ Found ready request #5: 8.5 ZK to 0x...

📝 Processing Mint Request #5
   ✅ Step 1: Execute Mint - Confirmed
   ✅ Step 2: Notify Staker - Confirmed

📊 EXECUTION SUMMARY
   Total Requests: 1
   Successful: 1
   Failed: 0
```

## Script 1: RequestMint.ts

### Purpose
Analyzes the current reward state and requests a mint via DelayMod to reach the desired APR.

### Usage

```bash
npx ts-node --transpileOnly script/rewards/RequestMint.ts -- --rate=<percentage> [--dry-run]
```

**Parameters:**
- `--rate=<percentage>` - Desired APR (e.g., 3.0 for 3%)
- `--dry-run` - Optional, test without creating request

**Examples:**
```bash
# Test what would be requested
npm run request-mint -- --rate=3.0 --dry-run

# Request mint for 3% APR
npm run request-mint -- --rate=3.0

# Request mint for 5.5% APR
npm run request-mint -- --rate=5.5
```

### What It Does

1. **Fetches current state** from ZkStaker contract:
   - Current reward rate (APR)
   - Total earning power (staked amount)
   - Reward end time

2. **Calculates required rewards**:
   - Compares current rate vs desired rate
   - Accounts for remaining rewards in current period
   - Calculates exact amount needed

3. **Requests mint** (if needed):
   - Calls `DelayMod.mint(staker, amount)`
   - Returns mint request ID
   - Displays when it can be executed

### Skip Conditions

The script will skip requesting if:
- Current rate ≥ desired rate
- Total earning power = 0 (no staking yet)
- Calculated amount = 0

### Output

**Success:**
```
✅ MINT REQUEST CREATED SUCCESSFULLY
   Request ID: 5
   Amount: 8.5 ZK
   Can execute after: 2025-11-04T10:30:00.000Z

📝 Next Steps:
   1. Wait until 2025-11-04T10:30:00.000Z
   2. Run: npx ts-node --transpileOnly script/rewards/ExecuteMints.ts
```

**No Action Needed:**
```
✅ Current rate (3.2%) is already at or above desired rate (3.0%)
   No action needed.
```

## Script 2: ExecuteMints.ts

### Purpose
Scans the DelayMod for pending mint requests that are ready to execute, executes them, and notifies the staker.

### Usage

```bash
npx ts-node --transpileOnly script/rewards/ExecuteMints.ts [--dry-run]
```

**Parameters:**
- `--dry-run` - Optional, scan and show what would execute without executing

**Examples:**
```bash
# Check what's ready without executing
npm run execute-mints -- --dry-run

# Execute all ready mints
npm run execute-mints
```

### What It Does

1. **Scans for pending requests**:
   - Queries `nextMintRequestId` from DelayMod
   - Iterates through all request IDs (0 to N-1)
   - Checks status of each request

2. **Filters ready requests**:
   - Not executed
   - Not vetoed
   - Delay period has elapsed

3. **Executes each ready request**:
   - Calls `DelayMod.executeMint(requestId)`
   - Calls `ZkStaker.notifyRewardAmount(amount)`
   - Reports success/failure for each

### Request States

The script handles multiple request states:

| State | Action |
|-------|--------|
| Ready | Execute and notify |
| Pending (in delay) | Report wait time remaining |
| Executed | Skip (already done) |
| Vetoed | Skip (rejected by governance) |

### Output

**Requests Found:**
```
🔍 Scanning for pending mint requests...
   Next Request ID: 6
   Scanning requests 0 to 5
   ✅ Found ready request #3: 5.2 ZK to 0x...
   ✅ Found ready request #5: 8.5 ZK to 0x...
   ⏳ Found pending request #4: Ready in 120s (2 minutes)

📋 Found 2 ready mint request(s)

📝 Processing Mint Request #3
   ✅ Step 1: Execute Mint - Confirmed in block 5962145
   ✅ Step 2: Notify Staker - Confirmed in block 5962146

📝 Processing Mint Request #5
   ✅ Step 1: Execute Mint - Confirmed in block 5962147
   ✅ Step 2: Notify Staker - Confirmed in block 5962148

📊 EXECUTION SUMMARY
   Total Requests: 2
   Successful: 2
   Failed: 0
```

**No Requests Ready:**
```
🔍 Scanning for pending mint requests...
   Next Request ID: 3
   Scanning requests 0 to 2
   ⏳ Found pending request #2: Ready in 300s (5 minutes)

✅ No ready mint requests found
   All pending requests are either executed or still in delay period
```

## Workflow Patterns

### Pattern 1: Manual Execution

```bash
# Morning: Request mints
npm run request-mint -- --rate=3.0
# Output: Can execute after 14:00 UTC

# Afternoon: Execute when ready
npm run execute-mints
```

### Pattern 2: Scheduled Execution

Set up cron jobs or CI/CD pipelines:

```bash
# Request mints daily at 9 AM
0 9 * * * cd /path/to/zkstaker && npm run request-mint -- --rate=3.0

# Check for ready mints every hour
0 * * * * cd /path/to/zkstaker && npm run execute-mints
```

The execute script is safe to run frequently - it only acts when requests are ready.

### Pattern 3: On-Demand

```bash
# Request immediately when needed
npm run request-mint -- --rate=5.0

# Come back later and execute
# (or let someone else execute it)
npm run execute-mints
```

## Error Handling

### RequestMint Errors

**Missing permissions:**
```
❌ Failed to request mint
   Error: AccessControl: account ... is missing role ...
```
→ Grant `MINTER_ROLE` on DelayMod to the Turnkey wallet

**Rate already sufficient:**
```
✅ Current rate (3.5%) is already at or above desired rate (3.0%)
   No action needed.
```
→ This is expected, no action needed

### ExecuteMints Errors

**Execute fails, notify skipped:**
```
❌ Failed to execute mint
   Error: Mint request has been vetoed
⚠️  Mint execution failed. Skipping notify step.
```
→ Request was vetoed by governance, normal operation

**Execute succeeds, notify fails:**
```
✅ Execute Mint - Confirmed
❌ Failed to notify staker
⚠️  CRITICAL: Mint executed but notify failed!
   Manual action required:
   Call staker.notifyRewardAmount(8500000000000000000) immediately!
```
→ Tokens are minted but staker not notified. Use **NotifyReward.ts** to recover (see [Disaster Recovery](#disaster-recovery-notifyrewardts) section).

## Disaster Recovery: NotifyReward.ts

### Purpose

`NotifyReward.ts` is a **disaster recovery tool** for when `ExecuteMints.ts` successfully mints tokens but fails to notify the staker contract. This can happen due to:

- Network issues (RPC timeout, connection loss)
- Gas price spikes between transactions
- Temporary node unavailability

In this scenario, ZK tokens have been minted to the staker contract, but the staker doesn't know about them. The tokens sit idle until `notifyRewardAmount` is called.

### When to Use

**Only use this script when you see this error from ExecuteMints.ts:**

```
✅ Execute Mint - Confirmed
❌ Failed to notify staker
⚠️  CRITICAL: Mint executed but notify failed!
   Manual action required:
   Call staker.notifyRewardAmount(8500000000000000000) immediately!
```

### Usage

```bash
# Dry run first to verify the amount
npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=<amount_in_wei> --dry-run

# Execute the recovery
npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=<amount_in_wei>
```

**Parameters:**
- `--amount=<wei>` - The exact amount from the failed ExecuteMints output (in wei)
- `--dry-run` - Optional, verify without executing

### Example Recovery

```bash
# From the error message: Call staker.notifyRewardAmount(8500000000000000000)
# Use that exact amount:

npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=8500000000000000000 --dry-run

# If dry run looks correct:
npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=8500000000000000000
```

### Important Notes

1. **Use the exact amount** from the ExecuteMints error message
2. **Act quickly** - until notify is called, the minted tokens aren't being distributed as rewards
3. **Don't use for normal operations** - this is only for recovery; use RequestMint + ExecuteMints for normal workflow
4. **Verify the mint succeeded** on a block explorer before running recovery

## Advanced Usage

### Check Specific Request

You can manually check any request:

```typescript
import { ethers } from "ethers";

const provider = new ethers.providers.JsonRpcProvider("https://...");
const delayMod = new ethers.Contract(DELAY_MOD_ADDRESS, ABI, provider);

const request = await delayMod.getMintRequest(5);
console.log({
  to: request.to,
  amount: request.amount.toString(),
  requestedAt: new Date(request.requestedAt * 1000),
  executed: request.executed,
  vetoed: request.vetoed
});
```

### Execute Specific Request

The ExecuteMints script processes all ready requests. To execute a specific one manually:

```bash
# Using cast (Foundry)
cast send $DELAY_MOD_ADDRESS "executeMint(uint256)" 5 --private-key $PRIVATE_KEY

# Then notify
cast send $ZKSTAKER_ADDRESS "notifyRewardAmount(uint256)" 8500000000000000000 --private-key $PRIVATE_KEY
```

## Comparison: Single vs Two-Script Approach

| Aspect | Single Script | Two Scripts |
|--------|--------------|-------------|
| **Delay Handling** | Must wait in-process | Can run separately |
| **Flexibility** | Tied to one execution | Run when convenient |
| **State Management** | Keeps state in memory | Stateless (queries DelayMod) |
| **Long Delays** | Impractical (hours/days) | Works perfectly |
| **Automation** | Requires long-running process | Easy cron/CI integration |
| **Multiple Requests** | One at a time | Batches all ready requests |
| **Recovery** | Complex if interrupted | Simple, just rerun |

## Permissions Required

### RequestMint.ts
- `MINTER_ROLE` on DelayMod contract

### ExecuteMints.ts
- **No special permissions!** Anyone can execute ready mints
- Only needs permissions to call `notifyRewardAmount` on staker (usually anyone can call this)

## Security Considerations

### Request Phase
- Only accounts with `MINTER_ROLE` can request mints
- Requests are subject to veto by governance
- All requests are logged on-chain

### Execute Phase
- Anyone can execute once delay period elapses
- Cannot execute vetoed requests
- Cannot execute twice (idempotent)
- Staker will reject incorrect notify amounts

### Veto Window
The delay period is the governance veto window. If a mint request is inappropriate:
1. Governance can call `delayMod.vetoMintRequest(requestId)`
2. ExecuteMints will skip vetoed requests
3. New request would need to be created

## Monitoring

### Check Pending Requests

```bash
# Dry run shows all pending requests and their status
npm run execute-mints -- --dry-run
```

### View On-Chain

Each request and execution is logged:
- `MintRequested` event: Request created
- `MintExecuted` event: Request executed
- `MintRequestVetoed` event: Request vetoed

View on block explorer:
```
https://explorer.zksync.io/address/{DELAY_MOD_ADDRESS}#events
```

## Troubleshooting

### "No ready mint requests found" but I just requested one

The delay period hasn't elapsed yet. Check the `Can execute after` timestamp from the RequestMint output.

### ExecuteMints finds requests but can't execute

Possible causes:
1. Request was vetoed by governance
2. Delay period calculation error (clock skew)
3. Network issues

Run with `--dry-run` to see detailed status of each request.

### Multiple failed requests

Check:
- Turnkey wallet has gas funds
- Network connectivity
- Staker contract is operational
- Not hitting rate limits

## Best Practices

1. **Always dry-run first** before live execution
2. **Monitor both scripts** in production
3. **Run ExecuteMints regularly** (every hour or more frequently)
4. **Alert on failures** especially notify failures
5. **Keep delay period reasonable** (hours, not days) for operational flexibility
6. **Document mint requests** with rate targets and reasoning
7. **Coordinate with governance** for expected mints

## Examples

### Daily Reward Top-Up

```bash
#!/bin/bash
# daily-rewards.sh

# Request mint to maintain 3% APR
npm run request-mint -- --rate=3.0

# Wait for the delay (if running in same session)
# Otherwise, schedule execute-mints separately

echo "Mint requested. Run execute-mints after delay period."
```

### Automated Pipeline

```yaml
# .github/workflows/rewards.yml
name: Manage Rewards

on:
  schedule:
    - cron: '0 9 * * *'  # Request daily at 9 AM
    - cron: '0 * * * *'  # Execute hourly

jobs:
  request:
    if: github.event.schedule == '0 9 * * *'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: npm install
      - run: npm run request-mint -- --rate=3.0

  execute:
    if: github.event.schedule == '0 * * * *'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: npm install
      - run: npm run execute-mints
```

## Migration from Single Script

If you were using the old RewardNotifier.ts:

**Old:**
```bash
npm run reward-notifier -- --rate=3.0
# Script waits for delay period...
```

**New:**
```bash
# Step 1: Request
npm run request-mint -- --rate=3.0

# Step 2: Execute (later, or scheduled)
npm run execute-mints
```

Benefits:
- No long-running processes
- Better for production
- More flexible timing
- Handles multiple requests

## Support

For issues:
1. Check this documentation
2. Run with `--dry-run` to diagnose
3. Review error messages (they include recovery steps)
4. Check contract events on block explorer
5. Verify permissions and configuration
