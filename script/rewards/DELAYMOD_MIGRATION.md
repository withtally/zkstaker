# DelayMod Migration Guide

## Overview

The RewardNotifier script has been updated to use **ZkMinterDelayV1 (DelayMod)** instead of directly minting from ZkCappedMinterV2. This change introduces a time-delayed minting pattern that provides a governance veto window.

## What Changed

### Previous Flow (Direct Minting)
1. **Mint**: `ZkCappedMinterV2.mint(staker, amount)` ✅
2. **Notify**: `ZkStaker.notifyRewardAmount(amount)` ✅

### New Flow (DelayMod)
1. **Request Mint**: `ZkMinterDelayV1.mint(staker, amount)` → Returns `mintRequestId` ✅
2. **Wait**: Delay period elapses (configurable, e.g., 24 hours) ⏰
3. **Execute Mint**: `ZkMinterDelayV1.executeMint(mintRequestId)` ✅
4. **Notify**: `ZkStaker.notifyRewardAmount(amount)` ✅

## Why This Change?

The DelayMod implements an **optimistic approval pattern** with the following benefits:

- **Governance Oversight**: Provides a time window for governance to veto inappropriate mint requests
- **Self-Serve Payments**: Authorized parties can request mints without requiring immediate approval
- **Audit Trail**: All mint requests are tracked on-chain with request IDs
- **Flexibility**: Delay period can be adjusted by governance

See: https://docs.zknation.io/zksync-governance-proposals/token-program-proposals-tpps/minter-mods-overview#delay-mod

## Configuration Changes

### Environment Variables

**Old:**
```bash
ZKCAPPED_MINTER_ADDRESS="0x721b6d77a58FaaF540bE49F28D668a46214Ba44c"
```

**New:**
```bash
DELAY_MOD_ADDRESS="0x..."  # Your deployed ZkMinterDelayV1 address
```

### Permission Changes

**Old:**
- Turnkey wallet needed `MINTER_ROLE` on `ZkCappedMinterV2`

**New:**
- Turnkey wallet needs `MINTER_ROLE` on `ZkMinterDelayV1` (DelayMod)
- The DelayMod itself has `MINTER_ROLE` on `ZkCappedMinterV2`

## Script Behavior

### Dry Run Mode
```bash
npx ts-node --transpileOnly script/rewards/RewardNotifier.ts -- --rate=3.0 --dry-run
```

Shows the full transaction plan including:
- Current mint delay period
- Three transactions that would be executed
- Wait time between request and execution

### Live Mode
```bash
npx ts-node --transpileOnly script/rewards/RewardNotifier.ts -- --rate=3.0
```

Executes all three transactions:
1. Creates mint request (Transaction 1)
2. **Waits automatically** for the delay period
3. Executes the mint (Transaction 2)
4. Notifies the staker (Transaction 3)

**⚠️ Important**: In live mode, the script will wait for the entire delay period before proceeding. If the delay is 24 hours, the script will run for 24+ hours.

## Error Handling

The script handles three failure scenarios:

### 1. Mint Request Fails
- **State**: Consistent (no changes made)
- **Action**: Fix permissions and retry

### 2. Execute Mint Fails
- **State**: Mint request created but not executed
- **Recovery**: Manually call `executeMint(mintRequestId)` after delay period
- **Script Output**: Provides exact recovery instructions with request ID

### 3. Notify Fails
- **State**: Tokens minted but staker not notified
- **Recovery**: Manually call `notifyRewardAmount(amount)`
- **Script Output**: Provides exact recovery instructions

## Migration Steps

### 1. Update Environment Variables

Edit your `.env` file:

```bash
# Replace ZKCAPPED_MINTER_ADDRESS with DELAY_MOD_ADDRESS
DELAY_MOD_ADDRESS="0xYourDelayModAddress"
```

### 2. Update Permissions

Grant `MINTER_ROLE` to your Turnkey wallet on the DelayMod:

```solidity
// On DelayMod contract
delayMod.grantRole(MINTER_ROLE, TURNKEY_WALLET_ADDRESS);
```

### 3. Test with Dry Run

```bash
npm run reward-notifier -- --rate=1.0 --dry-run
```

Verify:
- ✅ Script loads DelayMod address
- ✅ Shows mint delay period
- ✅ Plans three transactions
- ✅ No errors

### 4. Execute

```bash
npm run reward-notifier -- --rate=1.0
```

**Note**: Be prepared for the script to run for the duration of the delay period plus transaction time.

## DelayMod Contract Details

### Key Functions

```solidity
// Request a mint (returns mint request ID)
function mint(address _to, uint256 _amount) external returns (uint256 mintRequestId)

// Execute a mint after delay period
function executeMint(uint256 _mintRequestId) external

// Query mint delay
function mintDelay() view returns (uint48)

// Get mint request details
function getMintRequest(uint256 _mintRequestId) view returns (MintRequest memory)

// Veto a pending mint (VETO_ROLE only)
function vetoMintRequest(uint256 _mintRequestId) external
```

### MintRequest Structure

```solidity
struct MintRequest {
    address minter;      // Who requested the mint
    address to;          // Destination address
    uint256 amount;      // Amount to mint
    uint48 requestedAt;  // Timestamp of request
    bool executed;       // Has it been executed?
    bool vetoed;         // Has it been vetoed?
}
```

## Comparison Table

| Aspect | Direct Minting | DelayMod |
|--------|---------------|----------|
| Transactions | 2 | 3 |
| Execution Time | Immediate | Delayed |
| Governance Control | Pre-approval | Veto window |
| Automation | Full | Partial (wait required) |
| Audit Trail | Basic | Enhanced |
| Flexibility | Lower | Higher |

## Frequently Asked Questions

### Q: Can I skip the wait period?
**A**: No, the delay period is enforced by the contract and cannot be bypassed (unless you have VETO_ROLE and veto then re-request).

### Q: What happens if someone vetos my mint request?
**A**: The script will fail at the `executeMint` step with an error that the request was vetoed. You'll need to create a new mint request.

### Q: Can I execute the mint manually?
**A**: Yes! After the delay period, anyone can call `executeMint(mintRequestId)`. The script provides the exact command if it fails.

### Q: How do I find the current delay period?
**A**: The script queries and displays it at the start. You can also call `delayMod.mintDelay()` directly.

### Q: Can the delay period be changed?
**A**: Yes, by governance calling `updateMintDelay(newDelay)` on the DelayMod contract.

## Additional Resources

- [DelayMod Documentation](https://docs.zknation.io/zksync-governance-proposals/token-program-proposals-tpps/minter-mods-overview#delay-mod)
- [Source Code](https://github.com/zksync-association/zkminters/blob/main/src/ZkMinterDelayV1.sol)
- [Audit Report](https://github.com/zksync-association/zkminters/blob/main/audits/ZKMinterDelayModV1Review_final_with_fixes.pdf)

## Support

If you encounter issues during migration:
1. Verify all environment variables are set correctly
2. Check that permissions are granted on the DelayMod (not the CappedMinter)
3. Review the error messages - they contain detailed recovery instructions
4. Consult this guide and the main README
