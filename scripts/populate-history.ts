// scripts/populate-history.ts
import { Principal } from "@dfinity/principal";
import { Actor, HttpAgent } from "@dfinity/agent";
import { minter, newIdentity } from "../src/tests/e2e/identity";
import {
  multiBackend,
  tokenA,
  tokenB,
  tokenC,
  TOKEN_A,
  TOKEN_B,
  TOKEN_C,
  MULTI_BACKEND_ID,
  MULTI_TOKEN_ID,
  GOVERNANCE_TOKEN_ID,
  fundTestAccount,
} from "../src/tests/e2e/actor";

const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
  red: "\x1b[31m",
  magenta: "\x1b[35m",
};

function log(message: string, color: string = colors.reset) {
  console.log(`${color}${message}${colors.reset}`);
}

// Helper to safely stringify objects with BigInts
function safeStringify(obj: any): string {
  return JSON.stringify(obj, (key, value) =>
    typeof value === "bigint" ? value.toString() : value,
  );
}

// Generate price history with random walk
function generatePriceHistory(days: number): Array<{
  timestamp: bigint;
  prices: { tokenA: number; tokenB: number; tokenC: number };
}> {
  const history = [];
  const now = Date.now();
  const startTime = now - days * 24 * 60 * 60 * 1000;

  // Starting prices
  const startPrices = {
    tokenA: 10.0,
    tokenB: 5.0,
    tokenC: 20.0,
  };

  let prices = { ...startPrices };

  for (let day = 0; day < days; day++) {
    // Random walk with different volatilities and biases
    prices.tokenA *= 1 + (Math.random() - 0.48) * 0.05; // Slight positive bias
    prices.tokenB *= 1 + (Math.random() - 0.52) * 0.05; // Slight negative bias
    prices.tokenC *= 1 + (Math.random() - 0.46) * 0.05; // Stronger positive bias

    // Keep prices positive
    prices.tokenA = Math.max(0.1, prices.tokenA);
    prices.tokenB = Math.max(0.1, prices.tokenB);
    prices.tokenC = Math.max(0.1, prices.tokenC);

    const timestamp =
      BigInt(startTime + day * 24 * 60 * 60 * 1000) * BigInt(1_000_000);

    history.push({
      timestamp,
      prices: { ...prices },
    });
  }

  return history;
}

// Calculate optimal END STATE for 70/20/10 value distribution
function calculateOptimalEndState(
  finalPrices: { tokenA: number; tokenB: number; tokenC: number },
  startPrices: { tokenA: number; tokenB: number; tokenC: number },
): {
  backingRatios: { tokenA: number; tokenB: number; tokenC: number };
  performance: Array<{
    token: string;
    id: Principal;
    growth: number;
    allocation: number;
  }>;
  initialMultiPrice: number;
  finalMultiPrice: number;
} {
  // Calculate performance
  const performances = [
    {
      token: "Token A",
      id: TOKEN_A,
      key: "tokenA",
      growth: finalPrices.tokenA / startPrices.tokenA,
      startPrice: startPrices.tokenA,
      finalPrice: finalPrices.tokenA,
    },
    {
      token: "Token B",
      id: TOKEN_B,
      key: "tokenB",
      growth: finalPrices.tokenB / startPrices.tokenB,
      startPrice: startPrices.tokenB,
      finalPrice: finalPrices.tokenB,
    },
    {
      token: "Token C",
      id: TOKEN_C,
      key: "tokenC",
      growth: finalPrices.tokenC / startPrices.tokenC,
      startPrice: startPrices.tokenC,
      finalPrice: finalPrices.tokenC,
    },
  ].sort((a, b) => b.growth - a.growth);

  // Assign allocations: 70% best, 20% middle, 10% worst
  performances[0].allocation = 0.7;
  performances[1].allocation = 0.2;
  performances[2].allocation = 0.1;

  log(`\n📊 Performance-Based Allocation:`, colors.bright + colors.cyan);
  performances.forEach((p, i) => {
    const color = i === 0 ? colors.green : i === 1 ? colors.yellow : colors.red;
    log(
      `   ${i + 1}. ${p.token}: ${((p.growth - 1) * 100).toFixed(1)}% growth → ${p.allocation * 100}% allocation`,
      color,
    );
  });

  // Calculate INITIAL Multi price (equal weight portfolio)
  // Start with equal amounts: 1.5 A, 3.0 B, 0.5 C
  const initialBackingA = 1.5;
  const initialBackingB = 3.0;
  const initialBackingC = 0.5;
  const initialMultiPrice =
    initialBackingA * startPrices.tokenA +
    initialBackingB * startPrices.tokenB +
    initialBackingC * startPrices.tokenC;

  log(
    `\n💰 Initial MULTI price (equal weight): $${initialMultiPrice.toFixed(2)}`,
    colors.blue,
  );

  // Calculate FINAL backing ratios for 70/20/10 value split
  // We want the final MULTI value to be much higher due to rebalancing into winners

  // Calculate what the portfolio WOULD be worth if we kept initial ratios
  const unoptimizedValue =
    initialBackingA * finalPrices.tokenA +
    initialBackingB * finalPrices.tokenB +
    initialBackingC * finalPrices.tokenC;

  // Calculate the optimized portfolio value (should be higher!)
  // Assume we captured 80% of the rebalancing gains
  const rebalancingBonus = 1.5; // 50% bonus from smart rebalancing
  const finalMultiPrice = unoptimizedValue * rebalancingBonus;

  log(`   Unoptimized value: $${unoptimizedValue.toFixed(2)}`, colors.yellow);
  log(`   Optimized value: $${finalMultiPrice.toFixed(2)}`, colors.green);

  // Now calculate backing ratios that give us 70/20/10 at this value
  const backingRatios = {
    tokenA: 0,
    tokenB: 0,
    tokenC: 0,
  };

  performances.forEach((p) => {
    const targetValue = finalMultiPrice * p.allocation;
    const unitsNeeded = targetValue / p.finalPrice;

    if (p.key === "tokenA") backingRatios.tokenA = unitsNeeded;
    if (p.key === "tokenB") backingRatios.tokenB = unitsNeeded;
    if (p.key === "tokenC") backingRatios.tokenC = unitsNeeded;
  });

  log(`\n🎯 Final Backing Ratios for 70/20/10 split:`, colors.magenta);
  log(
    `   Token A: ${backingRatios.tokenA.toFixed(4)} units per MULTI`,
    colors.blue,
  );
  log(
    `   Token B: ${backingRatios.tokenB.toFixed(4)} units per MULTI`,
    colors.blue,
  );
  log(
    `   Token C: ${backingRatios.tokenC.toFixed(4)} units per MULTI`,
    colors.blue,
  );
  log(
    `\n📈 MULTI Price Growth: $${initialMultiPrice.toFixed(2)} → $${finalMultiPrice.toFixed(2)} (${((finalMultiPrice / initialMultiPrice - 1) * 100).toFixed(1)}% gain)`,
    colors.bright + colors.green,
  );

  return {
    backingRatios,
    performance: performances,
    initialMultiPrice,
    finalMultiPrice,
  };
}

// Generate backing history showing gradual rebalancing
function generateBackingHistory(
  priceHistory: Array<{ timestamp: bigint; prices: any }>,
  startPrices: { tokenA: number; tokenB: number; tokenC: number },
  optimalBackingRatios: { tokenA: number; tokenB: number; tokenC: number },
  initialMultiPrice: number,
  finalMultiPrice: number,
): {
  history: Array<{
    timestamp: bigint;
    supply: bigint;
    backingConfig: any;
  }>;
  finalState: {
    supply: bigint;
    backingConfig: any;
  };
} {
  const days = priceHistory.length;
  const history = [];

  // Initial "equal weight" ratios
  const initialRatios = {
    tokenA: 1.5,
    tokenB: 3.0,
    tokenC: 0.5,
  };

  for (let day = 0; day < days; day++) {
    const progress = day / days;
    const currentPrices = priceHistory[day].prices;

    // Supply grows over time
    const supply = 100_000 + 150_000 * progress;

    // Simulate gradual rebalancing
    // Early: mostly equal weight
    // Middle: start shifting based on performance
    // Late: converge to optimal 70/20/10

    // Use S-curve for smooth transition
    const rebalanceProgress = 1 / (1 + Math.exp(-10 * (progress - 0.5)));

    // Interpolate between initial and optimal ratios
    let backingA =
      initialRatios.tokenA * (1 - rebalanceProgress) +
      optimalBackingRatios.tokenA * rebalanceProgress;
    let backingB =
      initialRatios.tokenB * (1 - rebalanceProgress) +
      optimalBackingRatios.tokenB * rebalanceProgress;
    let backingC =
      initialRatios.tokenC * (1 - rebalanceProgress) +
      optimalBackingRatios.tokenC * rebalanceProgress;

    // Add realistic daily variation (±2%)
    const dailyNoise = () => 0.98 + Math.random() * 0.04;
    backingA *= dailyNoise();
    backingB *= dailyNoise();
    backingC *= dailyNoise();

    // Major rebalancing events
    if (day > 0 && day % 90 === 0) {
      // Jump closer to optimal on rebalance days
      const jumpStrength = 0.2;
      backingA =
        backingA * (1 - jumpStrength) +
        optimalBackingRatios.tokenA * jumpStrength;
      backingB =
        backingB * (1 - jumpStrength) +
        optimalBackingRatios.tokenB * jumpStrength;
      backingC =
        backingC * (1 - jumpStrength) +
        optimalBackingRatios.tokenC * jumpStrength;

      // Calculate current portfolio value
      const currentValue =
        backingA * currentPrices.tokenA +
        backingB * currentPrices.tokenB +
        backingC * currentPrices.tokenC;

      log(
        `   Day ${day}: Rebalancing - MULTI value: $${currentValue.toFixed(2)}`,
        colors.yellow,
      );
    }

    const backing = {
      supplyUnit: BigInt(100_000_000),
      totalSupply: BigInt(Math.floor(supply * 1e8)),
      backingPairs: [
        {
          token: TOKEN_A,
          backingUnit: BigInt(Math.floor(backingA * 1e8)),
        },
        {
          token: TOKEN_B,
          backingUnit: BigInt(Math.floor(backingB * 1e8)),
        },
        {
          token: TOKEN_C,
          backingUnit: BigInt(Math.floor(backingC * 1e8)),
        },
      ],
      multiToken: MULTI_TOKEN_ID,
    };

    history.push({
      timestamp: priceHistory[day].timestamp,
      supply: backing.totalSupply,
      backingConfig: backing,
    });
  }

  // Final state with exact optimal ratios
  const finalBacking = {
    supplyUnit: BigInt(100_000_000),
    totalSupply: BigInt(25000000000000), // 250,000 MULTI
    backingPairs: [
      {
        token: TOKEN_A,
        backingUnit: BigInt(Math.floor(optimalBackingRatios.tokenA * 1e8)),
      },
      {
        token: TOKEN_B,
        backingUnit: BigInt(Math.floor(optimalBackingRatios.tokenB * 1e8)),
      },
      {
        token: TOKEN_C,
        backingUnit: BigInt(Math.floor(optimalBackingRatios.tokenC * 1e8)),
      },
    ],
    multiToken: MULTI_TOKEN_ID,
  };

  // Replace last entry with exact optimal
  history[history.length - 1] = {
    timestamp: priceHistory[days - 1].timestamp,
    supply: finalBacking.totalSupply,
    backingConfig: finalBacking,
  };

  return {
    history,
    finalState: {
      supply: finalBacking.totalSupply,
      backingConfig: finalBacking,
    },
  };
}

// Initialize multi_backend with optimal state
async function setupMultiBackend(
  finalState: {
    supply: bigint;
    backingConfig: any;
  },
  finalPrices: { tokenA: number; tokenB: number; tokenC: number },
  finalMultiPrice: number,
) {
  log(
    "\n5️⃣ Setting up Multi Backend with optimal 70/20/10 allocation...",
    colors.yellow,
  );

  const adminBackend = await multiBackend(minter);
  const isInit = await adminBackend.isInitialized();

  if (!isInit) {
    log("   Initializing system with optimal backing ratios...", colors.cyan);

    // Approve tokens
    for (const [name, tokenId] of [
      ["Token A", TOKEN_A],
      ["Token B", TOKEN_B],
      ["Token C", TOKEN_C],
    ]) {
      const result = await adminBackend.approveToken({ canisterId: tokenId });
      if (
        "ok" in result ||
        ("err" in result && "TokenAlreadyApproved" in result.err)
      ) {
        log(`     ✔ ${name} approved`, colors.green);
      }
    }

    // Initialize with optimal backing configuration
    const config = {
      supplyUnit: finalState.backingConfig.supplyUnit,
      backingTokens: finalState.backingConfig.backingPairs.map((pair: any) => ({
        canisterId: pair.token,
        backingUnit: pair.backingUnit,
      })),
      multiToken: { canisterId: MULTI_TOKEN_ID },
      governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
    };

    const initResult = await adminBackend.initialize(config);
    if ("ok" in initResult) {
      log("     ✔ System initialized with optimal ratios", colors.green);
    } else if ("err" in initResult && "AlreadyInitialized" in initResult.err) {
      log("     ⚠ System already initialized", colors.yellow);
      return;
    } else {
      log(
        `     ✗ Failed to initialize: ${safeStringify(initResult)}`,
        colors.red,
      );
      return;
    }
  } else {
    log("   ⚠ System already initialized", colors.yellow);
    return;
  }

  // Create user to populate reserves
  const alice = newIdentity();
  log("\n   Creating user to populate reserves...", colors.cyan);

  // Calculate deposit amounts
  const backingA =
    Number(finalState.backingConfig.backingPairs[0].backingUnit) / 1e8;
  const backingB =
    Number(finalState.backingConfig.backingPairs[1].backingUnit) / 1e8;
  const backingC =
    Number(finalState.backingConfig.backingPairs[2].backingUnit) / 1e8;

  const targetSupply = 200000; // 200k MULTI
  const neededA = Math.ceil(backingA * targetSupply);
  const neededB = Math.ceil(backingB * targetSupply);
  const neededC = Math.ceil(backingC * targetSupply);

  log(
    `\n   Target MULTI price: $${finalMultiPrice.toFixed(2)}`,
    colors.bright + colors.green,
  );
  log(`   Required reserves for ${targetSupply} MULTI:`, colors.cyan);
  log(`     Token A: ${neededA} tokens`, colors.blue);
  log(`     Token B: ${neededB} tokens`, colors.blue);
  log(`     Token C: ${neededC} tokens`, colors.blue);

  // Fund user
  const fundAmount = BigInt(Math.max(neededA, neededB, neededC) * 2 * 1e8);
  const minterTokenA = await tokenA(minter);
  const minterTokenB = await tokenB(minter);
  const minterTokenC = await tokenC(minter);

  await fundTestAccount(minterTokenA, alice, fundAmount);
  await fundTestAccount(minterTokenB, alice, fundAmount);
  await fundTestAccount(minterTokenC, alice, fundAmount);
  log(`     ✔ User funded`, colors.green);

  // Deposit and issue
  const fee = BigInt(10_000);
  const aliceBackend = await multiBackend(alice);
  const aliceTokenA = await tokenA(alice);
  const aliceTokenB = await tokenB(alice);
  const aliceTokenC = await tokenC(alice);

  log("\n   Depositing tokens...", colors.cyan);
  const depositA = BigInt(Math.ceil(neededA * 1.2 * 1e8));
  const depositB = BigInt(Math.ceil(neededB * 1.2 * 1e8));
  const depositC = BigInt(Math.ceil(neededC * 1.2 * 1e8));

  for (const { tokenActor, tokenId, name, amount } of [
    {
      tokenActor: aliceTokenA,
      tokenId: TOKEN_A,
      name: "Token A",
      amount: depositA,
    },
    {
      tokenActor: aliceTokenB,
      tokenId: TOKEN_B,
      name: "Token B",
      amount: depositB,
    },
    {
      tokenActor: aliceTokenC,
      tokenId: TOKEN_C,
      name: "Token C",
      amount: depositC,
    },
  ]) {
    await tokenActor.icrc2_approve({
      spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
      amount: amount + fee,
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expected_allowance: [],
      expires_at: [],
    });

    const depositResult = await aliceBackend.deposit({
      token: tokenId,
      amount: amount,
    });

    if ("ok" in depositResult) {
      log(`     ✔ Deposited ${Number(amount) / 1e8} ${name}`, colors.green);
    }
  }

  // Issue MULTI tokens
  log("\n   Issuing MULTI tokens...", colors.cyan);
  const issueAmount = BigInt(targetSupply * 1e8);

  const issueResult = await aliceBackend.issue({ amount: issueAmount });
  if ("ok" in issueResult) {
    log(`     ✔ Issued ${targetSupply} MULTI tokens`, colors.green);
  } else {
    // Try smaller amount
    const fallbackAmount = BigInt(Math.floor(targetSupply * 0.75 * 1e8));
    const fallbackResult = await aliceBackend.issue({ amount: fallbackAmount });
    if ("ok" in fallbackResult) {
      log(`     ✔ Issued ${Number(fallbackAmount) / 1e8} MULTI`, colors.green);
    }
  }

  // Verify final state
  const systemInfo = await adminBackend.getSystemInfo();
  if ("ok" in systemInfo) {
    log(`\n   ✅ Final System State:`, colors.bright + colors.green);
    log(
      `   Total Supply: ${(Number(systemInfo.ok.totalSupply) / 1e8).toFixed(0)} MULTI`,
      colors.blue,
    );

    // Calculate actual value distribution
    log(`\n   📊 Value Distribution (70/20/10 target):`, colors.magenta);
    let totalValue = 0;
    const values: any = {};

    for (const backing of systemInfo.ok.backingTokens) {
      const symbol = backing.tokenInfo.symbol || "Token";
      const backingUnit = Number(backing.backingUnit) / 1e8;

      let price = 0;
      if (symbol === "a") price = finalPrices.tokenA;
      if (symbol === "b") price = finalPrices.tokenB;
      if (symbol === "c") price = finalPrices.tokenC;

      const value = backingUnit * price;
      values[symbol] = value;
      totalValue += value;
    }

    for (const [symbol, value] of Object.entries(values)) {
      const percentage = (((value as number) / totalValue) * 100).toFixed(1);
      const color =
        percentage > 50
          ? colors.green
          : percentage > 15
            ? colors.yellow
            : colors.red;
      log(`     ${symbol}: ${percentage}%`, color);
    }

    log(
      `\n   💰 MULTI Token Value: $${totalValue.toFixed(2)}`,
      colors.bright + colors.cyan,
    );
  }
}

async function populateHistory() {
  log(
    "\n🚀 Multi History Population Script - Portfolio Rebalancing Simulation",
    colors.bright + colors.cyan,
  );

  const days = parseInt(process.argv[2] || "730");
  log(
    `Simulating ${days} days of portfolio evolution from equal weight to 70/20/10...\n`,
    colors.yellow,
  );

  // Starting prices
  const startPrices = {
    tokenA: 10.0,
    tokenB: 5.0,
    tokenC: 20.0,
  };

  // Step 1: Generate price history
  log("1️⃣ Generating price movements...", colors.yellow);
  const priceHistory = generatePriceHistory(days);
  const finalPrices = priceHistory[priceHistory.length - 1].prices;

  // Step 2: Calculate optimal end state
  log("\n2️⃣ Calculating optimal portfolio allocation...", colors.yellow);
  const { backingRatios, initialMultiPrice, finalMultiPrice } =
    calculateOptimalEndState(finalPrices, startPrices);

  // Step 3: Generate backing history
  log("\n3️⃣ Generating rebalancing history...", colors.yellow);
  const { history: backingHistory, finalState } = generateBackingHistory(
    priceHistory,
    startPrices,
    backingRatios,
    initialMultiPrice,
    finalMultiPrice,
  );

  // Connect to history canister
  const MULTI_HISTORY_ID =
    process.env.CANISTER_ID_MULTI_HISTORY ||
    (await import("child_process"))
      .execSync("dfx canister id multi_history")
      .toString()
      .trim();

  log("\n4️⃣ Writing history to canister...", colors.yellow);
  const agent = new HttpAgent({ host: "http://localhost:4943" });
  await agent.fetchRootKey();

  const { idlFactory } = await import("../src/declarations/multi_history");
  const historyActor = Actor.createActor(idlFactory, {
    agent,
    canisterId: Principal.fromText(MULTI_HISTORY_ID),
  });

  // Batch write history
  const batchSize = 100;
  let successCount = 0;

  for (let i = 0; i < days; i += batchSize) {
    const batch = [];

    for (let j = i; j < Math.min(i + batchSize, days); j++) {
      const snapshot = backingHistory[j];
      const prices = priceHistory[j].prices;

      batch.push({
        timestamp: snapshot.timestamp,
        prices: [
          [TOKEN_A, BigInt(Math.floor(prices.tokenA * 1e8))],
          [TOKEN_B, BigInt(Math.floor(prices.tokenB * 1e8))],
          [TOKEN_C, BigInt(Math.floor(prices.tokenC * 1e8))],
        ],
        approvedTokens: [TOKEN_A, TOKEN_B, TOKEN_C],
        backing: snapshot.backingConfig,
      });
    }

    try {
      const count = await historyActor.recordSnapshotBatch(batch);
      successCount += Number(count);
      log(`   Progress: ${successCount}/${days} days`, colors.cyan);
    } catch (error) {
      log(`   Failed batch: ${error}`, colors.red);
    }
  }

  log(`   ✅ Populated ${successCount} days of history`, colors.green);

  // Step 5: Setup backend
  await setupMultiBackend(finalState, finalPrices, finalMultiPrice);

  log(
    `\n🎉 Complete! Portfolio rebalancing from equal weight to 70/20/10 over ${days} days!`,
    colors.bright + colors.green,
  );
  log(
    `   MULTI price grew from $${initialMultiPrice.toFixed(2)} to $${finalMultiPrice.toFixed(2)}!`,
    colors.bright + colors.cyan,
  );
}

// Run
populateHistory().catch((error) => {
  log(`\n❌ Error: ${error}`, colors.red);
  process.exit(1);
});
