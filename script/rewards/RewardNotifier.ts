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
const ZKCAPPED_MINTER_ADDRESS = process.env.ZKCAPPED_MINTER_ADDRESS;
const ZK_TOKEN_ADDRESS = process.env.ZK_TOKEN_ADDRESS;

// RPC Configuration
const ZKSYNC_RPC_URL = process.env.ZKSYNC_RPC_URL || "https://mainnet.era.zksync.io";

// Turnkey Configuration
const TURNKEY_ORGANIZATION_ID = process.env.TURNKEY_ORGANIZATION_ID;
const TURNKEY_API_PUBLIC_KEY = process.env.TURNKEY_API_PUBLIC_KEY;
const TURNKEY_API_PRIVATE_KEY = process.env.TURNKEY_API_PRIVATE_KEY;
const TURNKEY_WALLET_ADDRESS = process.env.TURNKEY_WALLET_ADDRESS;

// Reward Configuration
const REWARD_DURATION = 30 * 24 * 60 * 60; // 30 days in seconds
const SCALE_FACTOR = BigInt(10 ** 18); // Standard scaling factor used by Staker

// ============================================================================
// Contract ABIs (minimal required functions)
// ============================================================================

const STAKER_ABI = [
  "function scaledRewardRate() view returns (uint256)",
  "function rewardEndTime() view returns (uint256)",
  "function totalEarningPower() view returns (uint256)",
  "function REWARD_DURATION() view returns (uint256)",
  "function notifyRewardAmount(uint256 amount) external",
  "function REWARDS_TOKEN() view returns (address)"
];

const MINTER_ABI = [
  "function mint(address to, uint256 amount) external"
];

const ERC20_ABI = [
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)"
];

// ============================================================================
// Types
// ============================================================================

interface RewardState {
  scaledRewardRate: bigint;
  rewardEndTime: bigint;
  totalEarningPower: bigint;
  currentTimestamp: bigint;
  rewardDuration: bigint;
}

interface TransactionPlan {
  mintAmount: bigint;
  notifyAmount: bigint;
  newRewardRate: bigint;
  currentRate: bigint;
  desiredRate: bigint;
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Calculate the current effective reward rate as a percentage per year
 */
function calculateCurrentRatePercentage(
  scaledRewardRate: bigint,
  totalEarningPower: bigint
): number {
  if (totalEarningPower === 0n) {
    return 0;
  }

  // Calculate annual rewards: rewardRate * seconds_per_year
  const secondsPerYear = 365n * 24n * 60n * 60n;
  const annualRewards = scaledRewardRate * secondsPerYear;

  // Calculate percentage: (annualRewards / totalEarningPower) * 100
  // Divide by SCALE_FACTOR to unscale the rate
  const ratePercentage = Number(
    (annualRewards * 100n) / (totalEarningPower * SCALE_FACTOR)
  );

  return ratePercentage;
}

/**
 * Calculate how many rewards need to be added to reach the desired rate
 */
function calculateRequiredRewards(
  state: RewardState,
  desiredRatePercentage: number
): bigint {
  if (state.totalEarningPower === 0n) {
    console.log("⚠️  No staking power in the system yet");
    return 0n;
  }

  // Calculate desired annual rewards
  const desiredAnnualRewards =
    (state.totalEarningPower * BigInt(Math.floor(desiredRatePercentage * 100))) / 10000n;

  // Calculate desired scaled reward rate per second
  const secondsPerYear = 365n * 24n * 60n * 60n;
  const desiredScaledRate = (desiredAnnualRewards * SCALE_FACTOR) / secondsPerYear;

  // Check if we're already at or above the desired rate
  if (state.scaledRewardRate >= desiredScaledRate) {
    return 0n;
  }

  // Calculate remaining rewards in the current distribution period
  let remainingRewards = 0n;
  if (state.currentTimestamp < state.rewardEndTime) {
    const remainingTime = state.rewardEndTime - state.currentTimestamp;
    remainingRewards = (state.scaledRewardRate * remainingTime) / SCALE_FACTOR;
  }

  // Calculate total rewards needed for the desired rate over the full duration
  const totalRewardsNeeded = (desiredScaledRate * state.rewardDuration) / SCALE_FACTOR;

  // We need to add enough to reach the desired total (minus what's already remaining)
  const rewardsToAdd = totalRewardsNeeded - remainingRewards;

  return rewardsToAdd > 0n ? rewardsToAdd : 0n;
}

/**
 * Calculate what the new reward rate will be after adding rewards
 */
function calculateNewRewardRate(
  state: RewardState,
  rewardsToAdd: bigint
): bigint {
  let remainingRewards = 0n;

  if (state.currentTimestamp < state.rewardEndTime) {
    const remainingTime = state.rewardEndTime - state.currentTimestamp;
    remainingRewards = (state.scaledRewardRate * remainingTime) / SCALE_FACTOR;
  }

  const totalRewards = remainingRewards + rewardsToAdd;
  const newScaledRate = (totalRewards * SCALE_FACTOR) / state.rewardDuration;

  return newScaledRate;
}

// ============================================================================
// Main Script Functions
// ============================================================================

/**
 * Get the current state of the reward system
 */
async function getRewardState(
  provider: Provider
): Promise<RewardState> {
  const staker = new ethers.Contract(ZKSTAKER_ADDRESS, STAKER_ABI, provider);

  const [scaledRewardRate, rewardEndTime, totalEarningPower, rewardDuration] =
    await Promise.all([
      staker.scaledRewardRate(),
      staker.rewardEndTime(),
      staker.totalEarningPower(),
      staker.REWARD_DURATION(),
    ]);

  const currentBlock = await provider.getBlock("latest");
  const currentTimestamp = BigInt(currentBlock.timestamp);

  return {
    scaledRewardRate: BigInt(scaledRewardRate.toString()),
    rewardEndTime: BigInt(rewardEndTime.toString()),
    totalEarningPower: BigInt(totalEarningPower.toString()),
    currentTimestamp,
    rewardDuration: BigInt(rewardDuration.toString()),
  };
}

/**
 * Format ether for display (ethers v5 compatible)
 */
function formatEther(value: bigint): string {
  return ethers.utils.formatEther(value.toString());
}

/**
 * Create a transaction plan for updating rewards
 */
async function createTransactionPlan(
  state: RewardState,
  desiredRatePercentage: number
): Promise<TransactionPlan | null> {
  const currentRate = calculateCurrentRatePercentage(
    state.scaledRewardRate,
    state.totalEarningPower
  );

  console.log(`\n📊 Current Reward State:`);
  console.log(`   Current Rate: ${currentRate.toFixed(4)}% APR`);
  console.log(`   Desired Rate: ${desiredRatePercentage.toFixed(4)}% APR`);
  console.log(`   Total Earning Power: ${formatEther(state.totalEarningPower)} ZK`);
  console.log(`   Reward End Time: ${new Date(Number(state.rewardEndTime) * 1000).toISOString()}`);

  // Check if we need to do anything
  if (currentRate >= desiredRatePercentage) {
    console.log(`\n✅ Current rate (${currentRate.toFixed(4)}%) is already at or above desired rate (${desiredRatePercentage}%)`);
    console.log(`   No action needed.`);
    return null;
  }

  const rewardsToAdd = calculateRequiredRewards(state, desiredRatePercentage);

  if (rewardsToAdd === 0n) {
    console.log(`\n✅ No rewards needed to reach desired rate`);
    return null;
  }

  const newScaledRate = calculateNewRewardRate(state, rewardsToAdd);
  const newRate = calculateCurrentRatePercentage(newScaledRate, state.totalEarningPower);

  console.log(`\n📋 Transaction Plan:`);
  console.log(`   Rewards to Add: ${formatEther(rewardsToAdd)} ZK`);
  console.log(`   New Rate: ${newRate.toFixed(4)}% APR`);

  return {
    mintAmount: rewardsToAdd,
    notifyAmount: rewardsToAdd,
    newRewardRate: newScaledRate,
    currentRate: state.scaledRewardRate,
    desiredRate: BigInt(Math.floor(desiredRatePercentage * 100)),
  };
}

/**
 * Initialize Turnkey signer
 */
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

/**
 * Execute the reward notification transactions
 */
async function executeTransactions(
  signer: TurnkeySigner,
  plan: TransactionPlan,
  dryRun: boolean
): Promise<void> {
  console.log(`\n${"=".repeat(70)}`);
  console.log(`${dryRun ? "🔍 DRY RUN MODE" : "🚀 EXECUTING TRANSACTIONS"}`);
  console.log(`${"=".repeat(70)}`);

  const minter = new ethers.Contract(ZKCAPPED_MINTER_ADDRESS, MINTER_ABI, signer);
  const staker = new ethers.Contract(ZKSTAKER_ADDRESS, STAKER_ABI, signer);

  // Transaction 1: Mint rewards
  console.log(`\n📝 Transaction 1: Mint Rewards`);
  console.log(`   Contract: ${ZKCAPPED_MINTER_ADDRESS}`);
  console.log(`   Function: mint(address to, uint256 amount)`);
  console.log(`   To: ${ZKSTAKER_ADDRESS}`);
  console.log(`   Amount: ${formatEther(plan.mintAmount)} ZK`);

  if (dryRun) {
    console.log(`   Status: ⏭️  Skipped (dry run)`);
  } else {
    try {
      const mintTx = await minter.mint(ZKSTAKER_ADDRESS, plan.mintAmount);
      console.log(`   Tx Hash: ${mintTx.hash}`);
      console.log(`   Status: ⏳ Waiting for confirmation...`);

      const mintReceipt = await mintTx.wait();
      console.log(`   Status: ✅ Confirmed in block ${mintReceipt.blockNumber}`);
    } catch (error: any) {
      console.error(`   Status: ❌ Failed`);
      console.error(`   Error: ${error.message}`);
      throw new Error(
        "CRITICAL: Mint transaction failed. The staker contract has NOT been notified. " +
        "The system is in a consistent state, but no rewards were added."
      );
    }
  }

  // Transaction 2: Notify staker
  console.log(`\n📝 Transaction 2: Notify Staker`);
  console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
  console.log(`   Function: notifyRewardAmount(uint256 amount)`);
  console.log(`   Amount: ${formatEther(plan.notifyAmount)} ZK`);

  if (dryRun) {
    console.log(`   Status: ⏭️  Skipped (dry run)`);
  } else {
    try {
      const notifyTx = await staker.notifyRewardAmount(plan.notifyAmount);
      console.log(`   Tx Hash: ${notifyTx.hash}`);
      console.log(`   Status: ⏳ Waiting for confirmation...`);

      const notifyReceipt = await notifyTx.wait();
      console.log(`   Status: ✅ Confirmed in block ${notifyReceipt.blockNumber}`);
    } catch (error: any) {
      console.error(`   Status: ❌ Failed`);
      console.error(`   Error: ${error.message}`);
      throw new Error(
        "\n" +
        "=".repeat(70) + "\n" +
        "⚠️  CRITICAL STATE: MANUAL INTERVENTION REQUIRED ⚠️\n" +
        "=".repeat(70) + "\n\n" +
        "The mint transaction SUCCEEDED but the notify transaction FAILED.\n" +
        "The staker contract is now in a BAD STATE:\n\n" +
        `  - ${formatEther(plan.mintAmount)} ZK tokens have been minted to the staker\n` +
        "  - The staker has NOT been notified of these rewards\n" +
        "  - The reward rate has NOT been updated\n\n" +
        "TO FIX THIS STATE:\n\n" +
        "1. Verify the minted tokens are in the staker contract:\n" +
        `   Check balance at: ${ZKSTAKER_ADDRESS}\n\n` +
        "2. Call notifyRewardAmount manually with the correct amount:\n" +
        `   Contract: ${ZKSTAKER_ADDRESS}\n` +
        `   Function: notifyRewardAmount(uint256 ${plan.notifyAmount})\n` +
        `   Amount: ${plan.notifyAmount.toString()} (${formatEther(plan.notifyAmount)} ZK)\n\n` +
        "3. After successful notification, verify the new reward rate.\n\n" +
        "DO NOT run this script again until the state is fixed!\n" +
        "=".repeat(70)
      );
    }
  }

  console.log(`\n${"=".repeat(70)}`);
  console.log(`${dryRun ? "✅ Dry run completed successfully" : "✅ All transactions completed successfully"}`);
  console.log(`${"=".repeat(70)}`);
}

/**
 * Main execution function
 */
async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const desiredRateArg = args.find((arg) => arg.startsWith("--rate="));

  if (!desiredRateArg) {
    console.error("❌ Error: Missing required --rate parameter");
    console.log("\nUsage:");
    console.log("  npm run script script/RewardNotifier.ts -- --rate=<percentage> [--dry-run]");
    console.log("\nExample:");
    console.log("  npm run script script/RewardNotifier.ts -- --rate=3.0 --dry-run");
    console.log("  npm run script script/RewardNotifier.ts -- --rate=3.0");
    process.exit(1);
  }

  const desiredRatePercentage = parseFloat(desiredRateArg.split("=")[1]);

  if (isNaN(desiredRatePercentage) || desiredRatePercentage <= 0) {
    console.error("❌ Error: Invalid rate percentage. Must be a positive number.");
    process.exit(1);
  }

  // Validate required environment variables
  if (!ZKSTAKER_ADDRESS) {
    console.error("❌ Error: ZKSTAKER_ADDRESS is not set in environment variables");
    console.error("   Please set ZKSTAKER_ADDRESS in your .env file");
    process.exit(1);
  }

  if (!ZKCAPPED_MINTER_ADDRESS) {
    console.error("❌ Error: ZKCAPPED_MINTER_ADDRESS is not set in environment variables");
    console.error("   Please set ZKCAPPED_MINTER_ADDRESS in your .env file");
    process.exit(1);
  }

  if (!ZK_TOKEN_ADDRESS) {
    console.error("❌ Error: ZK_TOKEN_ADDRESS is not set in environment variables");
    console.error("   Please set ZK_TOKEN_ADDRESS in your .env file");
    process.exit(1);
  }

  console.log(`\n🎯 ZKStaker Reward Notifier`);
  console.log(`${"=".repeat(70)}`);
  console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);
  console.log(`Desired Rate: ${desiredRatePercentage}% APR`);
  console.log(`ZKStaker: ${ZKSTAKER_ADDRESS}`);
  console.log(`Minter: ${ZKCAPPED_MINTER_ADDRESS}`);
  console.log(`${"=".repeat(70)}`);

  // Initialize provider
  const provider = new ethers.providers.JsonRpcProvider(ZKSYNC_RPC_URL);

  // Get current reward state
  console.log(`\n🔍 Fetching current reward state...`);
  const state = await getRewardState(provider);

  // Create transaction plan
  const plan = await createTransactionPlan(state, desiredRatePercentage);

  if (!plan) {
    console.log(`\n👋 Exiting - no action required\n`);
    return;
  }

  // Initialize Turnkey signer (only if not dry run)
  let signer: TurnkeySigner;
  if (!dryRun) {
    console.log(`\n🔐 Initializing Turnkey signer...`);
    signer = initializeTurnkeySigner(provider);
    console.log(`   Signer address: ${TURNKEY_WALLET_ADDRESS}`);
  } else {
    // Create a dummy signer for dry run (won't be used)
    signer = null as any;
  }

  // Execute transactions
  await executeTransactions(signer, plan, dryRun);

  if (!dryRun) {
    // Verify the new state
    console.log(`\n🔍 Verifying new reward state...`);
    const newState = await getRewardState(provider);
    const newRate = calculateCurrentRatePercentage(
      newState.scaledRewardRate,
      newState.totalEarningPower
    );
    console.log(`   New Rate: ${newRate.toFixed(4)}% APR`);
    console.log(`   New Reward End Time: ${new Date(Number(newState.rewardEndTime) * 1000).toISOString()}`);
  }

  console.log();
}

// ============================================================================
// Script Entry Point
// ============================================================================

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n💥 Script failed:");
    console.error(error.message || error);
    process.exit(1);
  });
