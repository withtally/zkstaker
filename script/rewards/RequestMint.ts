import { config as dotEnvConfig } from "dotenv";
import { ethers, JsonRpcProvider, formatEther as ethersFormatEther } from "ethers";
import { TurnkeySigner } from "@turnkey/ethers";
import { TurnkeyClient } from "@turnkey/http";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { notifySlack } from "./slackNotify";

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
const REWARD_DURATION_DAYS = process.env.REWARD_DURATION_DAYS
  ? parseInt(process.env.REWARD_DURATION_DAYS, 10)
  : undefined; // Optional override; defaults to contract value if not set
const SCALE_FACTOR = BigInt(10 ** 18); // Standard scaling factor used by Staker
const RATE_TOLERANCE = 0.01; // 0.01% tolerance for rate comparison

// ============================================================================
// Contract ABIs
// ============================================================================

const STAKER_ABI = [
  "function scaledRewardRate() view returns (uint256)",
  "function rewardEndTime() view returns (uint256)",
  "function totalEarningPower() view returns (uint256)",
  "function REWARD_DURATION() view returns (uint256)",
  "function notifyRewardAmount(uint256 amount) external"
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
  // Contract uses SCALE_FACTOR^2 for scaledRewardRate
  const annualRewards = (scaledRewardRate * secondsPerYear) / (SCALE_FACTOR * SCALE_FACTOR);
  console.log("scaledRewardRate", scaledRewardRate);
  console.log("annualRewards", annualRewards);
  const ratePercentage = (Number(annualRewards) / Number(totalEarningPower)) * 100;
  console.log("ratePercentage", ratePercentage);
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
  // Contract uses SCALE_FACTOR^2 for scaledRewardRate
  const desiredScaledRate = (desiredAnnualRewards * SCALE_FACTOR * SCALE_FACTOR) / secondsPerYear;

  if (state.scaledRewardRate >= desiredScaledRate) {
    return 0n;
  }

  let remainingRewards = 0n;
  if (state.currentTimestamp < state.rewardEndTime) {
    const remainingTime = state.rewardEndTime - state.currentTimestamp;
    remainingRewards = (state.scaledRewardRate * remainingTime) / (SCALE_FACTOR * SCALE_FACTOR);
  }

  const totalRewardsNeeded = (desiredScaledRate * state.rewardDuration) / (SCALE_FACTOR * SCALE_FACTOR);
  const rewardsToAdd = totalRewardsNeeded - remainingRewards;

  return rewardsToAdd > 0n ? rewardsToAdd : 0n;
}

function formatEther(value: bigint): string {
  return ethersFormatEther(value);
}

// ============================================================================
// Main Functions
// ============================================================================

async function getRewardState(provider: JsonRpcProvider): Promise<RewardState> {
  const staker = new ethers.Contract(ZKSTAKER_ADDRESS!, STAKER_ABI, provider);

  const [scaledRewardRate, rewardEndTime, totalEarningPower, contractRewardDuration] =
    await Promise.all([
      staker.scaledRewardRate(),
      staker.rewardEndTime(),
      staker.totalEarningPower(),
      staker.REWARD_DURATION(),
    ]);

  const currentBlock = await provider.getBlock("latest");
  const currentTimestamp = BigInt(currentBlock.timestamp);

  // Use env override if set, otherwise use contract value
  const rewardDuration = REWARD_DURATION_DAYS !== undefined
    ? BigInt(REWARD_DURATION_DAYS * 24 * 60 * 60)
    : BigInt(contractRewardDuration.toString());

  return {
    scaledRewardRate: BigInt(scaledRewardRate.toString()),
    rewardEndTime: BigInt(rewardEndTime.toString()),
    totalEarningPower: BigInt(totalEarningPower.toString()),
    currentTimestamp,
    rewardDuration,
  };
}

function initializeTurnkeySigner(provider: JsonRpcProvider): TurnkeySigner {
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
  const provider = new JsonRpcProvider(ZKSYNC_RPC_URL);

  // Get current reward state
  console.log(`\n🔍 Fetching current reward state...`);
  const state = await getRewardState(provider);

  const currentRate = calculateCurrentRatePercentage(
    state.scaledRewardRate,
    state.totalEarningPower
  );

  const rewardDurationDays = Number(state.rewardDuration) / (24 * 60 * 60);
  console.log(`\n📊 Current Reward State:`);
  console.log(`   Current Rate: ${currentRate.toFixed(4)}% APR`);
  console.log(`   Desired Rate: ${desiredRatePercentage.toFixed(4)}% APR`);
  console.log(`   Total Earning Power: ${formatEther(state.totalEarningPower)} ZK`);
  console.log(`   Reward Duration: ${rewardDurationDays} days${REWARD_DURATION_DAYS !== undefined ? ' (from env)' : ' (from contract)'}`);
  console.log(`   Reward End Time: ${new Date(Number(state.rewardEndTime) * 1000).toISOString()}`);

  // Check if rate is within tolerance - no action needed
  if (Math.abs(currentRate - desiredRatePercentage) < RATE_TOLERANCE) {
    console.log(`\n✅ Current rate (${currentRate.toFixed(4)}%) is within tolerance of desired rate (${desiredRatePercentage}%)`);
    console.log(`   No action needed.\n`);
    return;
  }

  // Check if rate is too high - need to lower it by calling notifyRewardAmount(0)
  if (currentRate > desiredRatePercentage) {
    console.log(`\n📉 Current rate (${currentRate.toFixed(4)}%) is above desired rate (${desiredRatePercentage}%)`);
    console.log(`   Will call notifyRewardAmount(0) to lower rate by spreading rewards over new duration.`);

    // Calculate remaining rewards and projected new rate
    let remainingRewards = 0n;
    if (state.currentTimestamp < state.rewardEndTime) {
      const remainingTime = state.rewardEndTime - state.currentTimestamp;
      remainingRewards = (state.scaledRewardRate * remainingTime) / (SCALE_FACTOR * SCALE_FACTOR);
    }

    const newScaledRate = (remainingRewards * SCALE_FACTOR * SCALE_FACTOR) / state.rewardDuration;
    const projectedRate = calculateCurrentRatePercentage(newScaledRate, state.totalEarningPower);
    console.log(`   Remaining rewards: ${formatEther(remainingRewards)} ZK`);
    console.log(`   Projected new rate: ${projectedRate.toFixed(4)}% APR`);

    if (dryRun) {
      console.log(`\n${"=".repeat(70)}`);
      console.log(`🔍 DRY RUN - Would call notifyRewardAmount(0) on ZKStaker`);
      console.log(`${"=".repeat(70)}`);
      console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
      console.log(`   Function: notifyRewardAmount(uint256 amount)`);
      console.log(`   Amount: 0 ZK`);
      console.log(`\n✅ Dry run completed successfully\n`);
      return;
    }

    // Initialize Turnkey signer and call notifyRewardAmount(0)
    console.log(`\n🔐 Initializing Turnkey signer...`);
    const signer = initializeTurnkeySigner(provider);
    console.log(`   Signer address: ${TURNKEY_WALLET_ADDRESS}`);

    console.log(`\n${"=".repeat(70)}`);
    console.log(`🚀 LOWERING REWARD RATE`);
    console.log(`${"=".repeat(70)}`);

    const staker = new ethers.Contract(ZKSTAKER_ADDRESS!, STAKER_ABI, signer);

    console.log(`\n📝 Calling notifyRewardAmount(0)...`);
    console.log(`   Contract: ${ZKSTAKER_ADDRESS}`);
    console.log(`   Function: notifyRewardAmount(uint256 amount)`);
    console.log(`   Amount: 0 ZK`);

    try {
      const notifyTx = await staker.notifyRewardAmount(0);
      console.log(`   Tx Hash: ${notifyTx.hash}`);
      console.log(`   Status: ⏳ Waiting for confirmation...`);

      const receipt = await notifyTx.wait();
      console.log(`   Status: ✅ Confirmed in block ${receipt.blockNumber}`);

      // Fetch new state to confirm
      const newState = await getRewardState(provider);
      const newRate = calculateCurrentRatePercentage(newState.scaledRewardRate, newState.totalEarningPower);

      console.log(`\n${"=".repeat(70)}`);
      console.log(`✅ REWARD RATE LOWERED SUCCESSFULLY`);
      console.log(`${"=".repeat(70)}`);
      console.log(`   Previous Rate: ${currentRate.toFixed(4)}% APR`);
      console.log(`   New Rate: ${newRate.toFixed(4)}% APR`);
      console.log(`   New Reward End Time: ${new Date(Number(newState.rewardEndTime) * 1000).toISOString()}`);
      console.log(`${"=".repeat(70)}\n`);

      await notifySlack(
        `*Rate Lowered*\n` +
        `Previous rate: ${currentRate.toFixed(4)}% APR\n` +
        `New rate: ${newRate.toFixed(4)}% APR\n` +
        `New reward end: ${new Date(Number(newState.rewardEndTime) * 1000).toISOString()}\n` +
        `Tx: \`${notifyTx.hash}\``
      );
    } catch (error: any) {
      console.error(`\n❌ Failed to call notifyRewardAmount`);
      console.error(`   Error: ${error.message}`);
      await notifySlack(
        `*Failed to lower reward rate*\n` +
        `Attempted: notifyRewardAmount(0) on ZKStaker\n` +
        `Error: ${error.message}`,
        "error"
      );
      process.exit(1);
    }

    return;
  }

  // Rate is too low - need to add rewards via DelayMod
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

      await notifySlack(
        `*Mint Requested*\n` +
        `Amount: ${formatEther(rewardsToAdd)} ZK\n` +
        `Request ID: ${mintRequestId}\n` +
        `Current rate: ${currentRate.toFixed(4)}% APR | Target: ${desiredRatePercentage.toFixed(4)}% APR\n` +
        `Execute after: ${executeAfter.toISOString()}\n` +
        `Tx: \`${mintRequestTx.hash}\``
      );
    } catch (e) {
      console.log(`\n✅ Mint request created (unable to determine request ID)`);
      console.log(`   Run ExecuteMints.ts after the delay period to execute pending mints\n`);

      await notifySlack(
        `*Mint Requested*\n` +
        `Amount: ${formatEther(rewardsToAdd)} ZK\n` +
        `Current rate: ${currentRate.toFixed(4)}% APR | Target: ${desiredRatePercentage.toFixed(4)}% APR\n` +
        `Tx: \`${mintRequestTx.hash}\`\n` +
        `_(Request ID could not be determined)_`
      );
    }
  } catch (error: any) {
    console.error(`\n❌ Failed to request mint`);
    console.error(`   Error: ${error.message}`);
    await notifySlack(
      `*Failed to request mint*\n` +
      `Attempted: ${formatEther(rewardsToAdd)} ZK via DelayMod\n` +
      `Target rate: ${desiredRatePercentage.toFixed(4)}% APR\n` +
      `Error: ${error.message}`,
      "error"
    );
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch(async (error) => {
    console.error("\n💥 Script failed:");
    console.error(error.message || error);
    await notifySlack(
      `*RequestMint script crashed*\nError: ${error.message || error}`,
      "error"
    );
    process.exit(1);
  });
