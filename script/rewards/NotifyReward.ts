/**
 * NotifyReward.ts - Disaster Recovery Script
 *
 * PURPOSE:
 * This script is a disaster recovery tool for when ExecuteMints.ts successfully
 * mints tokens but fails to call notifyRewardAmount on the staker contract.
 *
 * WHEN TO USE:
 * Only use this script when you see this error from ExecuteMints.ts:
 *
 *   ✅ Execute Mint - Confirmed
 *   ❌ Failed to notify staker
 *   ⚠️  CRITICAL: Mint executed but notify failed!
 *      Manual action required:
 *      Call staker.notifyRewardAmount(8500000000000000000) immediately!
 *
 * This can happen due to network issues, gas spikes, or RPC unavailability
 * between the mint and notify transactions.
 *
 * WHAT IT DOES:
 * Calls notifyRewardAmount(amount) on the ZKStaker contract to inform it about
 * tokens that have already been minted to it. This resumes reward distribution.
 *
 * DO NOT USE FOR NORMAL OPERATIONS:
 * Use RequestMint.ts + ExecuteMints.ts for the normal reward workflow.
 * This script is only for recovering from failed notify calls.
 *
 * USAGE:
 *   npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=<wei> [--dry-run]
 *
 * Use the exact amount from the ExecuteMints error message.
 */

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
  "function notifyRewardAmount(uint256 amount) external",
  "function scaledRewardRate() view returns (uint256)",
  "function rewardEndTime() view returns (uint256)"
];

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

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const amountArg = args.find((arg) => arg.startsWith("--amount="));

  if (!amountArg) {
    console.error("❌ Error: Missing required --amount parameter");
    console.log("\n🚨 DISASTER RECOVERY SCRIPT");
    console.log("   Use this only when ExecuteMints.ts mints succeed but notify fails.");
    console.log("   For normal operations, use RequestMint.ts + ExecuteMints.ts instead.");
    console.log("\nUsage:");
    console.log("  npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=<amount_in_wei> [--dry-run]");
    console.log("\nExample (use the exact amount from the ExecuteMints error message):");
    console.log("  npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=8500000000000000000 --dry-run");
    console.log("  npx ts-node --transpileOnly script/rewards/NotifyReward.ts -- --amount=8500000000000000000");
    process.exit(1);
  }

  const amountStr = amountArg.split("=")[1];
  let amount: bigint;

  try {
    amount = BigInt(amountStr);
  } catch (error) {
    console.error("❌ Error: Invalid amount. Must be a valid integer (in wei).");
    console.log("\nTip: Use wei units. For example:");
    console.log("  - 1 ZK = 1000000000000000000 wei (1e18)");
    console.log("  - 0.1 ZK = 100000000000000000 wei (1e17)");
    process.exit(1);
  }

  if (amount <= 0n) {
    console.error("❌ Error: Amount must be greater than 0");
    process.exit(1);
  }

  // Validate required environment variables
  if (!ZKSTAKER_ADDRESS) {
    console.error("❌ Error: ZKSTAKER_ADDRESS is not set in environment variables");
    process.exit(1);
  }

  console.log(`\n🚨 ZKStaker Notify Reward (Disaster Recovery)`);
  console.log(`${"=".repeat(70)}`);
  console.log(`⚠️  This script is for recovering from failed ExecuteMints notify calls.`);
  console.log(`   For normal operations, use RequestMint.ts + ExecuteMints.ts instead.`);
  console.log(`${"=".repeat(70)}`);
  console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);
  console.log(`ZKStaker: ${ZKSTAKER_ADDRESS}`);
  console.log(`Amount: ${formatEther(amount)} ZK`);
  console.log(`${"=".repeat(70)}`);

  // Initialize provider
  const provider = new ethers.providers.JsonRpcProvider(ZKSYNC_RPC_URL);
  const stakerRead = new ethers.Contract(ZKSTAKER_ADDRESS, STAKER_ABI, provider);

  // Get current state
  console.log(`\n📊 Fetching current state...`);
  try {
    const currentEndTime = await stakerRead.rewardEndTime();
    console.log(`\n📋 Current State:`);
    console.log(`   Current Reward End: ${new Date(Number(currentEndTime.toString()) * 1000).toISOString()}`);
  } catch (error) {
    console.log(`   (Unable to fetch current state - contract may not be initialized yet)`);
  }

  if (dryRun) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`🔍 DRY RUN - Would call notifyRewardAmount`);
    console.log(`${"=".repeat(70)}`);
    console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
    console.log(`   Function: notifyRewardAmount(uint256 amount)`);
    console.log(`   Amount: ${amount} (${formatEther(amount)} ZK)`);
    console.log(`\n✅ Dry run completed successfully\n`);
    return;
  }

  // Initialize Turnkey signer
  console.log(`\n🔐 Initializing Turnkey signer...`);
  const signer = initializeTurnkeySigner(provider);
  console.log(`   Signer address: ${TURNKEY_WALLET_ADDRESS}`);

  const staker = new ethers.Contract(ZKSTAKER_ADDRESS, STAKER_ABI, signer);

  // Notify staker
  console.log(`\n${"=".repeat(70)}`);
  console.log(`🚀 NOTIFYING STAKER`);
  console.log(`${"=".repeat(70)}`);
  console.log(`\n📝 Calling notifyRewardAmount...`);
  console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
  console.log(`   Function: notifyRewardAmount(uint256 amount)`);
  console.log(`   Amount: ${amount} (${formatEther(amount)} ZK)`);

  try {
    const notifyTx = await staker.notifyRewardAmount(amount);
    console.log(`   Tx Hash: ${notifyTx.hash}`);
    console.log(`   Status: ⏳ Waiting for confirmation...`);

    const receipt = await notifyTx.wait();
    console.log(`   Status: ✅ Confirmed in block ${receipt.blockNumber}`);

    // Get new end time
    const newEndTime = await stakerRead.rewardEndTime();
    const newScaledRate = await stakerRead.scaledRewardRate();

    console.log(`\n${"=".repeat(70)}`);
    console.log(`✅ NOTIFICATION SUCCESSFUL`);
    console.log(`${"=".repeat(70)}`);
    console.log(`   New Reward End Time: ${new Date(Number(newEndTime.toString()) * 1000).toISOString()}`);
    console.log(`   New Scaled Rate: ${newScaledRate.toString()}`);
    console.log(`${"=".repeat(70)}\n`);
  } catch (error: any) {
    console.error(`\n❌ Failed to notify staker`);
    console.error(`   Error: ${error.message}`);

    if (error.message.includes("not notifier")) {
      console.error(`\n💡 Solution:`);
      console.error(`   Grant NOTIFIER_ROLE to your Turnkey wallet:`);
      console.error(`   staker.grantRole(NOTIFIER_ROLE, ${TURNKEY_WALLET_ADDRESS})`);
    }

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
