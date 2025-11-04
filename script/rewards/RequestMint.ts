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

// Reward Configuration
const REWARD_DURATION = 30 * 24 * 60 * 60; // 30 days in seconds
const SCALE_FACTOR = BigInt(10 ** 18); // Standard scaling factor used by Staker

// ============================================================================
// Contract ABIs
// ============================================================================

const STAKER_ABI = [
  "function scaledRewardRate() view returns (uint256)",
  "function rewardEndTime() view returns (uint256)",
  "function totalEarningPower() view returns (uint256)",
  "function REWARD_DURATION() view returns (uint256)"
];

const DELAY_MOD_ABI = [
  "function mint(address to, uint256 amount) external returns (uint256)",
  "function mintDelay() view returns (uint48)",
  "function nextMintRequestId() view returns (uint256)"
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

// ============================================================================
// Utility Functions
// ============================================================================

function calculateCurrentRatePercentage(
  scaledRewardRate: bigint,
  totalEarningPower: bigint
): number {
  if (totalEarningPower === 0n) {
    return 0;
  }
  const secondsPerYear = 365n * 24n * 60n * 60n;
  const annualRewards = scaledRewardRate * secondsPerYear;
  const ratePercentage = Number(
    (annualRewards * 100n) / (totalEarningPower * SCALE_FACTOR)
  );
  return ratePercentage;
}

function calculateRequiredRewards(
  state: RewardState,
  desiredRatePercentage: number
): bigint {
  if (state.totalEarningPower === 0n) {
    console.log("⚠️  No staking power in the system yet");
    return 0n;
  }

  const desiredAnnualRewards =
    (state.totalEarningPower * BigInt(Math.floor(desiredRatePercentage * 100))) / 10000n;

  const secondsPerYear = 365n * 24n * 60n * 60n;
  const desiredScaledRate = (desiredAnnualRewards * SCALE_FACTOR) / secondsPerYear;

  if (state.scaledRewardRate >= desiredScaledRate) {
    return 0n;
  }

  let remainingRewards = 0n;
  if (state.currentTimestamp < state.rewardEndTime) {
    const remainingTime = state.rewardEndTime - state.currentTimestamp;
    remainingRewards = (state.scaledRewardRate * remainingTime) / SCALE_FACTOR;
  }

  const totalRewardsNeeded = (desiredScaledRate * state.rewardDuration) / SCALE_FACTOR;
  const rewardsToAdd = totalRewardsNeeded - remainingRewards;

  return rewardsToAdd > 0n ? rewardsToAdd : 0n;
}

function formatEther(value: bigint): string {
  return ethers.utils.formatEther(value.toString());
}

// ============================================================================
// Main Functions
// ============================================================================

async function getRewardState(provider: Provider): Promise<RewardState> {
  const staker = new ethers.Contract(ZKSTAKER_ADDRESS!, STAKER_ABI, provider);

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

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const desiredRateArg = args.find((arg) => arg.startsWith("--rate="));

  if (!desiredRateArg) {
    console.error("❌ Error: Missing required --rate parameter");
    console.log("\nUsage:");
    console.log("  npx ts-node --transpileOnly script/rewards/RequestMint.ts -- --rate=<percentage> [--dry-run]");
    console.log("\nExample:");
    console.log("  npx ts-node --transpileOnly script/rewards/RequestMint.ts -- --rate=3.0 --dry-run");
    console.log("  npx ts-node --transpileOnly script/rewards/RequestMint.ts -- --rate=3.0");
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
    process.exit(1);
  }

  if (!DELAY_MOD_ADDRESS) {
    console.error("❌ Error: DELAY_MOD_ADDRESS is not set in environment variables");
    process.exit(1);
  }

  console.log(`\n🎯 ZKStaker Mint Request`);
  console.log(`${"=".repeat(70)}`);
  console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);
  console.log(`Desired Rate: ${desiredRatePercentage}% APR`);
  console.log(`ZKStaker: ${ZKSTAKER_ADDRESS}`);
  console.log(`DelayMod: ${DELAY_MOD_ADDRESS}`);
  console.log(`${"=".repeat(70)}`);

  // Initialize provider
  const provider = new ethers.providers.JsonRpcProvider(ZKSYNC_RPC_URL);

  // Get current reward state
  console.log(`\n🔍 Fetching current reward state...`);
  const state = await getRewardState(provider);

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
    console.log(`   No action needed.\n`);
    return;
  }

  const rewardsToAdd = calculateRequiredRewards(state, desiredRatePercentage);

  if (rewardsToAdd === 0n) {
    console.log(`\n✅ No rewards needed to reach desired rate\n`);
    return;
  }

  console.log(`\n📋 Mint Request:`);
  console.log(`   Rewards to Mint: ${formatEther(rewardsToAdd)} ZK`);

  // Get mint delay
  const delayModRead = new ethers.Contract(DELAY_MOD_ADDRESS, DELAY_MOD_ABI, provider);
  const mintDelay = await delayModRead.mintDelay();
  const mintDelaySeconds = Number(mintDelay.toString());
  console.log(`   Mint Delay: ${mintDelaySeconds} seconds (${Math.floor(mintDelaySeconds / 60)} minutes)`);

  if (dryRun) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`🔍 DRY RUN - Would request mint via DelayMod`);
    console.log(`${"=".repeat(70)}`);
    console.log(`   Contract: ${DELAY_MOD_ADDRESS}`);
    console.log(`   Function: mint(address to, uint256 amount)`);
    console.log(`   To: ${ZKSTAKER_ADDRESS}`);
    console.log(`   Amount: ${formatEther(rewardsToAdd)} ZK`);
    console.log(`\n✅ Dry run completed successfully\n`);
    return;
  }

  // Initialize Turnkey signer
  console.log(`\n🔐 Initializing Turnkey signer...`);
  const signer = initializeTurnkeySigner(provider);
  console.log(`   Signer address: ${TURNKEY_WALLET_ADDRESS}`);

  // Request mint
  console.log(`\n${"=".repeat(70)}`);
  console.log(`🚀 REQUESTING MINT`);
  console.log(`${"=".repeat(70)}`);

  const delayMod = new ethers.Contract(DELAY_MOD_ADDRESS, DELAY_MOD_ABI, signer);

  console.log(`\n📝 Requesting mint via DelayMod...`);
  console.log(`   Contract: ${DELAY_MOD_ADDRESS}`);
  console.log(`   Function: mint(address to, uint256 amount)`);
  console.log(`   To: ${ZKSTAKER_ADDRESS}`);
  console.log(`   Amount: ${formatEther(rewardsToAdd)} ZK`);

  try {
    const mintRequestTx = await delayMod.mint(ZKSTAKER_ADDRESS, rewardsToAdd);
    console.log(`   Tx Hash: ${mintRequestTx.hash}`);
    console.log(`   Status: ⏳ Waiting for confirmation...`);

    const mintRequestReceipt = await mintRequestTx.wait();
    console.log(`   Status: ✅ Confirmed in block ${mintRequestReceipt.blockNumber}`);

    // Try to get the mint request ID
    try {
      const nextId = await delayMod.nextMintRequestId();
      const mintRequestId = BigInt(nextId.toString()) - 1n;
      console.log(`   Mint Request ID: ${mintRequestId}`);

      const executeAfter = new Date((Number(mintRequestReceipt.blockTimestamp) + mintDelaySeconds) * 1000);
      console.log(`\n${"=".repeat(70)}`);
      console.log(`✅ MINT REQUEST CREATED SUCCESSFULLY`);
      console.log(`${"=".repeat(70)}`);
      console.log(`   Request ID: ${mintRequestId}`);
      console.log(`   Amount: ${formatEther(rewardsToAdd)} ZK`);
      console.log(`   Can execute after: ${executeAfter.toISOString()}`);
      console.log(`\n📝 Next Steps:`);
      console.log(`   1. Wait until ${executeAfter.toISOString()}`);
      console.log(`   2. Run: npx ts-node --transpileOnly script/rewards/ExecuteMints.ts`);
      console.log(`${"=".repeat(70)}\n`);
    } catch (e) {
      console.log(`\n✅ Mint request created (unable to determine request ID)`);
      console.log(`   Run ExecuteMints.ts after the delay period to execute pending mints\n`);
    }
  } catch (error: any) {
    console.error(`\n❌ Failed to request mint`);
    console.error(`   Error: ${error.message}`);
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
