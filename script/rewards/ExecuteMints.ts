import { config as dotEnvConfig } from "dotenv";
import { ethers } from "ethers";
import { TurnkeySigner } from "@turnkey/ethers";
import { TurnkeyClient } from "@turnkey/http";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import type { Provider } from "@ethersproject/providers";

// Load environment variables
dotEnvConfig();

// ============================================================================
// Configuration Constants
// ============================================================================

// Contract Addresses
const ZKSTAKER_ADDRESS = process.env.ZKSTAKER_ADDRESS;
const DELAY_MOD_ADDRESS = process.env.DELAY_MOD_ADDRESS;

// RPC Configuration
const ZKSYNC_RPC_URL = process.env.ZKSYNC_RPC_URL || "https://mainnet.era.zksync.io";

// Turnkey Configuration
const TURNKEY_ORGANIZATION_ID = process.env.TURNKEY_ORGANIZATION_ID;
const TURNKEY_API_PUBLIC_KEY = process.env.TURNKEY_API_PUBLIC_KEY;
const TURNKEY_API_PRIVATE_KEY = process.env.TURNKEY_API_PRIVATE_KEY;
const TURNKEY_WALLET_ADDRESS = process.env.TURNKEY_WALLET_ADDRESS;

// ============================================================================
// Contract ABIs
// ============================================================================

const STAKER_ABI = [
  "function notifyRewardAmount(uint256 amount) external"
];

const DELAY_MOD_ABI = [
  "function executeMint(uint256 mintRequestId) external",
  "function getMintRequest(uint256 mintRequestId) view returns (tuple(address minter, address to, uint256 amount, uint48 requestedAt, bool executed, bool vetoed))",
  "function mintDelay() view returns (uint48)",
  "function nextMintRequestId() view returns (uint256)"
];

// ============================================================================
// Types
// ============================================================================

interface MintRequest {
  id: bigint;
  minter: string;
  to: string;
  amount: bigint;
  requestedAt: number;
  executed: boolean;
  vetoed: boolean;
}

// ============================================================================
// Utility Functions
// ============================================================================

function formatEther(value: bigint): string {
  return ethers.utils.formatEther(value.toString());
}

function initializeTurnkeySigner(provider: Provider): TurnkeySigner {
  if (!TURNKEY_ORGANIZATION_ID || !TURNKEY_API_PUBLIC_KEY || !TURNKEY_API_PRIVATE_KEY || !TURNKEY_WALLET_ADDRESS) {
    throw new Error(
      "Missing Turnkey configuration. Please set TURNKEY_ORGANIZATION_ID, TURNKEY_API_PUBLIC_KEY, " +
      "TURNKEY_API_PRIVATE_KEY, and TURNKEY_WALLET_ADDRESS in your .env file"
    );
  }

  const stamper = new ApiKeyStamper({
    apiPublicKey: TURNKEY_API_PUBLIC_KEY,
    apiPrivateKey: TURNKEY_API_PRIVATE_KEY,
  });

  const turnkeyClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    stamper
  );

  return new TurnkeySigner({
    client: turnkeyClient,
    organizationId: TURNKEY_ORGANIZATION_ID,
    signWith: TURNKEY_WALLET_ADDRESS,
  }).connect(provider);
}

// ============================================================================
// Main Functions
// ============================================================================

async function findPendingMintRequests(
  delayMod: ethers.Contract,
  currentTimestamp: number,
  mintDelay: number
): Promise<MintRequest[]> {
  console.log(`\n🔍 Scanning for pending mint requests...`);

  const nextMintRequestId = await delayMod.nextMintRequestId();
  const nextId = BigInt(nextMintRequestId.toString());

  console.log(`   Next Request ID: ${nextId}`);
  console.log(`   Scanning requests 0 to ${nextId - 1n}`);

  const pendingRequests: MintRequest[] = [];

  // Scan all mint requests
  for (let i = 0n; i < nextId; i++) {
    try {
      const request = await delayMod.getMintRequest(i);
      const mintRequest: MintRequest = {
        id: i,
        minter: request.minter,
        to: request.to,
        amount: BigInt(request.amount.toString()),
        requestedAt: Number(request.requestedAt.toString()),
        executed: request.executed,
        vetoed: request.vetoed,
      };

      // Check if request is pending (not executed, not vetoed)
      if (!mintRequest.executed && !mintRequest.vetoed) {
        // Check if it's ready to execute (delay has elapsed)
        const canExecuteAt = mintRequest.requestedAt + mintDelay;
        if (currentTimestamp >= canExecuteAt) {
          pendingRequests.push(mintRequest);
          console.log(`   ✅ Found ready request #${i}: ${formatEther(mintRequest.amount)} ZK to ${mintRequest.to}`);
        } else {
          const waitTime = canExecuteAt - currentTimestamp;
          console.log(`   ⏳ Found pending request #${i}: Ready in ${waitTime}s (${Math.floor(waitTime / 60)} minutes)`);
        }
      }
    } catch (e) {
      // Request doesn't exist or error reading it, skip
    }
  }

  return pendingRequests;
}

async function executeMintRequest(
  delayMod: ethers.Contract,
  staker: ethers.Contract,
  request: MintRequest,
  dryRun: boolean
): Promise<boolean> {
  console.log(`\n${"=".repeat(70)}`);
  console.log(`📝 Processing Mint Request #${request.id}`);
  console.log(`${"=".repeat(70)}`);
  console.log(`   To: ${request.to}`);
  console.log(`   Amount: ${formatEther(request.amount)} ZK`);
  console.log(`   Requested At: ${new Date(request.requestedAt * 1000).toISOString()}`);

  if (dryRun) {
    console.log(`\n   [DRY RUN] Would execute:`);
    console.log(`   1. delayMod.executeMint(${request.id})`);
    console.log(`   2. staker.notifyRewardAmount(${request.amount})`);
    return true;
  }

  // Step 1: Execute mint
  console.log(`\n📝 Step 1: Execute Mint`);
  console.log(`   Contract: ${DELAY_MOD_ADDRESS}`);
  console.log(`   Function: executeMint(${request.id})`);

  // Double-check the mint hasn't been executed already
  try {
    const currentRequest = await delayMod.getMintRequest(request.id);
    if (currentRequest.executed) {
      console.log(`   Status: ⏭️  Mint already executed, skipping...`);
      return true;
    }
  } catch (error: any) {
    console.error(`   Status: ⚠️  Could not verify mint status`);
    console.error(`   Error: ${error.message}`);
    console.error(`   Proceeding with execution attempt...`);
  }

  try {
    const executeTx = await delayMod.executeMint(request.id);
    console.log(`   Tx Hash: ${executeTx.hash}`);
    console.log(`   Status: ⏳ Waiting for confirmation...`);

    const executeReceipt = await executeTx.wait();
    console.log(`   Status: ✅ Confirmed in block ${executeReceipt.blockNumber}`);
  } catch (error: any) {
    console.error(`   Status: ❌ Failed to execute mint`);
    console.error(`   Error: ${error.message}`);
    console.error(`\n⚠️  Mint execution failed. Skipping notify step.`);
    return false;
  }

  // Step 2: Notify staker
  console.log(`\n📝 Step 2: Notify Staker`);
  console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
  console.log(`   Function: notifyRewardAmount(${request.amount})`);
  console.log(`   Amount: ${formatEther(request.amount)} ZK`);

  try {
    const notifyTx = await staker.notifyRewardAmount(request.amount);
    console.log(`   Tx Hash: ${notifyTx.hash}`);
    console.log(`   Status: ⏳ Waiting for confirmation...`);

    const notifyReceipt = await notifyTx.wait();
    console.log(`   Status: ✅ Confirmed in block ${notifyReceipt.blockNumber}`);
    console.log(`\n✅ Successfully processed mint request #${request.id}`);
    return true;
  } catch (error: any) {
    console.error(`   Status: ❌ Failed to notify staker`);
    console.error(`   Error: ${error.message}`);
    console.error(`\n⚠️  CRITICAL: Mint executed but notify failed!`);
    console.error(`   Manual action required:`);
    console.error(`   Call staker.notifyRewardAmount(${request.amount}) immediately!`);
    return false;
  }
}

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");

  // Validate required environment variables
  if (!ZKSTAKER_ADDRESS) {
    console.error("❌ Error: ZKSTAKER_ADDRESS is not set in environment variables");
    process.exit(1);
  }

  if (!DELAY_MOD_ADDRESS) {
    console.error("❌ Error: DELAY_MOD_ADDRESS is not set in environment variables");
    process.exit(1);
  }

  console.log(`\n🎯 ZKStaker Execute Pending Mints`);
  console.log(`${"=".repeat(70)}`);
  console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);
  console.log(`ZKStaker: ${ZKSTAKER_ADDRESS}`);
  console.log(`DelayMod: ${DELAY_MOD_ADDRESS}`);
  console.log(`${"=".repeat(70)}`);

  // Initialize provider
  const provider = new ethers.providers.JsonRpcProvider(ZKSYNC_RPC_URL);
  const delayModRead = new ethers.Contract(DELAY_MOD_ADDRESS, DELAY_MOD_ABI, provider);

  // Get current timestamp and mint delay
  const currentBlock = await provider.getBlock("latest");
  const currentTimestamp = currentBlock.timestamp;
  const mintDelay = await delayModRead.mintDelay();
  const mintDelaySeconds = Number(mintDelay.toString());

  console.log(`\n⏱️  Configuration:`);
  console.log(`   Current Time: ${new Date(currentTimestamp * 1000).toISOString()}`);
  console.log(`   Mint Delay: ${mintDelaySeconds} seconds (${Math.floor(mintDelaySeconds / 60)} minutes)`);

  // Find pending mint requests
  const pendingRequests = await findPendingMintRequests(
    delayModRead,
    currentTimestamp,
    mintDelaySeconds
  );

  if (pendingRequests.length === 0) {
    console.log(`\n✅ No ready mint requests found`);
    console.log(`   All pending requests are either executed or still in delay period\n`);
    return;
  }

  console.log(`\n📋 Found ${pendingRequests.length} ready mint request(s)`);

  if (dryRun) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`🔍 DRY RUN MODE - No transactions will be executed`);
    console.log(`${"=".repeat(70)}`);

    for (const request of pendingRequests) {
      await executeMintRequest(delayModRead, delayModRead, request, true);
    }

    console.log(`\n${"=".repeat(70)}`);
    console.log(`✅ Dry run completed successfully`);
    console.log(`${"=".repeat(70)}\n`);
    return;
  }

  // Initialize Turnkey signer for live execution
  console.log(`\n🔐 Initializing Turnkey signer...`);
  const signer = initializeTurnkeySigner(provider);
  console.log(`   Signer address: ${TURNKEY_WALLET_ADDRESS}`);

  const delayMod = new ethers.Contract(DELAY_MOD_ADDRESS, DELAY_MOD_ABI, signer);
  const staker = new ethers.Contract(ZKSTAKER_ADDRESS, STAKER_ABI, signer);

  // Execute each pending mint request
  let successCount = 0;
  let failCount = 0;

  for (const request of pendingRequests) {
    const success = await executeMintRequest(delayMod, staker, request, false);
    if (success) {
      successCount++;
    } else {
      failCount++;
    }
  }

  // Summary
  console.log(`\n${"=".repeat(70)}`);
  console.log(`📊 EXECUTION SUMMARY`);
  console.log(`${"=".repeat(70)}`);
  console.log(`   Total Requests: ${pendingRequests.length}`);
  console.log(`   Successful: ${successCount}`);
  console.log(`   Failed: ${failCount}`);
  console.log(`${"=".repeat(70)}\n`);

  if (failCount > 0) {
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n💥 Script failed:");
    console.error(error.message || error);
    process.exit(1);
  });
