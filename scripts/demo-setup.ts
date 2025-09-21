import { Principal } from "@dfinity/principal";
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
  multiToken,
  fundTestAccount,
} from "../src/tests/e2e/actor";

// Colors for console output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  red: "\x1b[31m",
};

function log(message: string, color: string = colors.reset) {
  console.log(`${color}${message}${colors.reset}`);
}

function logSection(title: string) {
  console.log("");
  log(`${"=".repeat(60)}`, colors.bright);
  log(title, colors.bright + colors.cyan);
  log(`${"=".repeat(60)}`, colors.bright);
}

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Helper to check if system is initialized
async function checkSystemState() {
  const backend = await multiBackend(minter);
  const isInit = await backend.isInitialized();

  if (isInit) {
    const systemInfo = await backend.getSystemInfo();
    if ("ok" in systemInfo) {
      return {
        initialized: true,
        totalSupply: systemInfo.ok.totalSupply,
        backingTokens: systemInfo.ok.backingTokens.length,
      };
    }
  }

  return { initialized: false, totalSupply: BigInt(0), backingTokens: 0 };
}

async function initializeSystem() {
  logSection("🚀 Initializing Multi Token System");

  const adminBackend = await multiBackend(minter);

  // Approve tokens
  log("Approving backing tokens...", colors.yellow);
  for (const [name, tokenId] of [
    ["Token A", TOKEN_A],
    ["Token B", TOKEN_B],
    ["Token C", TOKEN_C],
  ]) {
    const result = await adminBackend.approveToken({ canisterId: tokenId });
    if ("ok" in result) {
      log(`  ✔ ${name} approved`, colors.green);
    } else if ("err" in result && "TokenAlreadyApproved" in result.err) {
      log(`  ✔ ${name} already approved`, colors.green);
    } else {
      log(`  ✗ Failed to approve ${name}`, colors.red);
    }
  }

  // Initialize with backing configuration
  log("\nInitializing backing configuration...", colors.yellow);
  const config = {
    supplyUnit: BigInt(100_000_000), // 1 MULTI token
    backingTokens: [
      {
        canisterId: TOKEN_A,
        backingUnit: BigInt(150_000_000), // 1.5 Token A per MULTI
      },
      {
        canisterId: TOKEN_B,
        backingUnit: BigInt(300_000_000), // 3 Token B per MULTI
      },
      {
        canisterId: TOKEN_C,
        backingUnit: BigInt(50_000_000), // 0.5 Token C per MULTI
      },
    ],
    multiToken: { canisterId: MULTI_TOKEN_ID },
    governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
  };

  const initResult = await adminBackend.initialize(config);
  if ("ok" in initResult) {
    log("  ✔ System initialized successfully", colors.green);
    log(
      `  Supply Unit: ${(Number(config.supplyUnit) / 1e8).toFixed(2)} MULTI`,
      colors.blue,
    );
    log("  Backing ratios:", colors.blue);
    log("    - 1 MULTI = 1.5 Token A", colors.blue);
    log("    - 1 MULTI = 3.0 Token B", colors.blue);
    log("    - 1 MULTI = 0.5 Token C", colors.blue);
  } else if ("err" in initResult && "AlreadyInitialized" in initResult.err) {
    log("  ✔ System already initialized", colors.green);
  } else {
    log("  ✗ Initialization failed", colors.red);
    console.error(initResult);
  }
}

async function performDemoOperations() {
  logSection("🎭 Starting Demo Operations");

  // Create demo users
  const alice = newIdentity();
  const bob = newIdentity();

  log("Creating demo users:", colors.yellow);
  log(
    `  Alice: ${alice.getPrincipal().toString().slice(0, 10)}...`,
    colors.blue,
  );
  log(`  Bob: ${bob.getPrincipal().toString().slice(0, 10)}...`, colors.blue);

  // Fund demo users with tokens
  log("\nFunding demo users with backing tokens...", colors.yellow);

  const fundAmount = BigInt(100000000000000); // 1,000,000 tokens (enough for all operations)

  // Create token instances for minter
  const minterTokenA = await tokenA(minter);
  const minterTokenB = await tokenB(minter);
  const minterTokenC = await tokenC(minter);

  await Promise.all([
    fundTestAccount(minterTokenA, alice, fundAmount),
    fundTestAccount(minterTokenB, alice, fundAmount),
    fundTestAccount(minterTokenC, alice, fundAmount),
    fundTestAccount(minterTokenA, bob, fundAmount),
    fundTestAccount(minterTokenB, bob, fundAmount),
    fundTestAccount(minterTokenC, bob, fundAmount),
  ]);

  log("  ✔ Users funded with 1,000,000 of each token", colors.green);

  // Alice deposits and issues
  logSection("👩 Alice: Depositing and Issuing MULTI");

  const aliceBackend = await multiBackend(alice);
  const depositAmount = BigInt(50000000000000); // 500,000 tokens
  const fee = BigInt(10_000);

  // Create token instances for Alice
  const aliceTokenA = await tokenA(alice);
  const aliceTokenB = await tokenB(alice);
  const aliceTokenC = await tokenC(alice);

  // Deposit each token type
  for (const { token, tokenId, name } of [
    { token: aliceTokenA, tokenId: TOKEN_A, name: "Token A" },
    { token: aliceTokenB, tokenId: TOKEN_B, name: "Token B" },
    { token: aliceTokenC, tokenId: TOKEN_C, name: "Token C" },
  ]) {
    log(`\nDepositing ${name}...`, colors.yellow);

    // Approve
    await token.icrc2_approve({
      spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
      amount: depositAmount + fee,
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expected_allowance: [],
      expires_at: [],
    });

    // Deposit
    const depositResult = await aliceBackend.deposit({
      token: tokenId,
      amount: depositAmount,
    });

    if ("ok" in depositResult) {
      log(
        `  ✔ Deposited ${(Number(depositAmount) / 1e8).toFixed(2)} ${name}`,
        colors.green,
      );
    }
  }

  await sleep(2000); // Wait for UI to update

  // Issue MULTI tokens - using specific amount to show calculations
  log("\nIssuing MULTI tokens...", colors.yellow);
  const issueAmount = BigInt(5495400000000); // 54,954 MULTI tokens (must be multiple of supply unit)

  // Show what this requires in backing tokens
  log(
    `  Requesting: ${(Number(issueAmount) / 1e8).toFixed(2)} MULTI tokens`,
    colors.yellow,
  );
  log("  This requires:", colors.cyan);
  log(
    `    - ${((Number(issueAmount) * 1.5) / 1e8).toFixed(2)} Token A (1.5x ratio)`,
    colors.cyan,
  );
  log(
    `    - ${((Number(issueAmount) * 3.0) / 1e8).toFixed(2)} Token B (3.0x ratio)`,
    colors.cyan,
  );
  log(
    `    - ${((Number(issueAmount) * 0.5) / 1e8).toFixed(2)} Token C (0.5x ratio)`,
    colors.cyan,
  );

  const issueResult = await aliceBackend.issue({ amount: issueAmount });
  if ("ok" in issueResult) {
    log(
      `  ✔ Issued ${(Number(issueAmount) / 1e8).toFixed(2)} MULTI tokens`,
      colors.green,
    );

    // Check balance
    const balanceResult = await aliceBackend.getMultiTokenBalance(
      alice.getPrincipal(),
    );
    if ("ok" in balanceResult) {
      log(
        `  Alice's MULTI balance: ${(Number(balanceResult.ok) / 1e8).toFixed(2)} MULTI`,
        colors.blue,
      );
    }
  }

  // Show system state
  await sleep(3000);
  await showSystemState();

  // Bob does similar operations
  logSection("👨 Bob: Depositing and Issuing MULTI");

  const bobBackend = await multiBackend(bob);

  // Create token instances for Bob
  const bobTokenA = await tokenA(bob);
  const bobTokenB = await tokenB(bob);
  const bobTokenC = await tokenC(bob);

  // Bob deposits (simplified - same pattern as Alice)
  for (const { token, tokenId, name } of [
    { token: bobTokenA, tokenId: TOKEN_A, name: "Token A" },
    { token: bobTokenB, tokenId: TOKEN_B, name: "Token B" },
    { token: bobTokenC, tokenId: TOKEN_C, name: "Token C" },
  ]) {
    await token.icrc2_approve({
      spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
      amount: depositAmount + fee,
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expected_allowance: [],
      expires_at: [],
    });

    await bobBackend.deposit({
      token: tokenId,
      amount: depositAmount,
    });
  }

  log(
    `  ✔ Bob deposited ${(Number(depositAmount) / 1e8).toFixed(2)} of each token`,
    colors.green,
  );

  // Bob issues less MULTI
  const bobIssueAmount = BigInt(1234500000000); // 12,345 MULTI tokens
  log(
    `\nBob issuing ${(Number(bobIssueAmount) / 1e8).toFixed(2)} MULTI tokens...`,
    colors.yellow,
  );
  await bobBackend.issue({ amount: bobIssueAmount });
  log(
    `  ✔ Bob issued ${(Number(bobIssueAmount) / 1e8).toFixed(2)} MULTI tokens`,
    colors.green,
  );

  const bobBalanceResult = await bobBackend.getMultiTokenBalance(
    bob.getPrincipal(),
  );
  if ("ok" in bobBalanceResult) {
    log(
      `  Bob's MULTI balance: ${(Number(bobBalanceResult.ok) / 1e8).toFixed(2)} MULTI`,
      colors.blue,
    );
  }

  await sleep(3000);
  await showSystemState();

  // Alice redeems some MULTI
  logSection("🔄 Alice: Redeeming MULTI tokens");

  const redeemAmount = BigInt(2391900000000); // 23,919 MULTI tokens
  log(
    `\nRedeeming ${(Number(redeemAmount) / 1e8).toFixed(2)} MULTI tokens...`,
    colors.yellow,
  );

  // Show what Alice will receive back
  log("  Alice will receive back:", colors.cyan);
  log(
    `    - ${((Number(redeemAmount) * 1.5) / 1e8).toFixed(2)} Token A`,
    colors.cyan,
  );
  log(
    `    - ${((Number(redeemAmount) * 3.0) / 1e8).toFixed(2)} Token B`,
    colors.cyan,
  );
  log(
    `    - ${((Number(redeemAmount) * 0.5) / 1e8).toFixed(2)} Token C`,
    colors.cyan,
  );

  const redeemResult = await aliceBackend.redeem({ amount: redeemAmount });
  if ("ok" in redeemResult) {
    log("  ✔ Redemption successful", colors.green);

    // Check new balance
    const newBalanceResult = await aliceBackend.getMultiTokenBalance(
      alice.getPrincipal(),
    );
    if ("ok" in newBalanceResult) {
      log(
        `  Alice's new MULTI balance: ${(Number(newBalanceResult.ok) / 1e8).toFixed(2)} MULTI`,
        colors.blue,
      );
    }

    // Show updated virtual balances
    log("\n  Alice's virtual balances after redemption:", colors.yellow);
    for (const [tokenId, name] of [
      [TOKEN_A, "Token A"],
      [TOKEN_B, "Token B"],
      [TOKEN_C, "Token C"],
    ]) {
      const vbResult = await aliceBackend.getVirtualBalance(
        alice.getPrincipal(),
        tokenId as any,
      );
      if ("ok" in vbResult) {
        log(
          `    ${name}: ${(Number(vbResult.ok) / 1e8).toFixed(2)}`,
          colors.blue,
        );
      }
    }
  }

  await sleep(3000);
  await showSystemState();

  // More operations over time
  logSection("⚡ Rapid Operations Demo");

  const operations = [
    { user: "Bob", action: "issue", amount: BigInt(789100000000) }, // 7,891 MULTI
    { user: "Alice", action: "redeem", amount: BigInt(456700000000) }, // 4,567 MULTI
    { user: "Bob", action: "issue", amount: BigInt(999900000000) }, // 9,999 MULTI
    { user: "Alice", action: "issue", amount: BigInt(333300000000) }, // 3,333 MULTI
    { user: "Bob", action: "redeem", amount: BigInt(111100000000) }, // 1,111 MULTI
  ];

  for (let i = 0; i < operations.length; i++) {
    const op = operations[i];
    log(`\nOperation ${i + 1}:`, colors.yellow);

    if (op.user === "Bob") {
      if (op.action === "issue") {
        await bobBackend.issue({ amount: op.amount });
        log(
          `  Bob issued ${(Number(op.amount) / 1e8).toFixed(2)} MULTI`,
          colors.blue,
        );
      } else {
        await bobBackend.redeem({ amount: op.amount });
        log(
          `  Bob redeemed ${(Number(op.amount) / 1e8).toFixed(2)} MULTI`,
          colors.magenta,
        );
      }
    } else {
      if (op.action === "issue") {
        await aliceBackend.issue({ amount: op.amount });
        log(
          `  Alice issued ${(Number(op.amount) / 1e8).toFixed(2)} MULTI`,
          colors.blue,
        );
      } else {
        await aliceBackend.redeem({ amount: op.amount });
        log(
          `  Alice redeemed ${(Number(op.amount) / 1e8).toFixed(2)} MULTI`,
          colors.magenta,
        );
      }
    }

    await sleep(1500);
  }

  // Show final balances
  log("\n📊 Final User Balances:", colors.bright + colors.yellow);

  const aliceFinalBalance = await aliceBackend.getMultiTokenBalance(
    alice.getPrincipal(),
  );
  if ("ok" in aliceFinalBalance) {
    log(
      `  Alice: ${(Number(aliceFinalBalance.ok) / 1e8).toFixed(2)} MULTI`,
      colors.green,
    );
  }

  const bobFinalBalance = await bobBackend.getMultiTokenBalance(
    bob.getPrincipal(),
  );
  if ("ok" in bobFinalBalance) {
    log(
      `  Bob: ${(Number(bobFinalBalance.ok) / 1e8).toFixed(2)} MULTI`,
      colors.green,
    );
  }

  // Final state
  await showSystemState();
}

async function showSystemState() {
  logSection("📊 Current System State");

  const backend = await multiBackend(minter);
  const systemInfoResult = await backend.getSystemInfo();

  if ("ok" in systemInfoResult) {
    const info = systemInfoResult.ok;

    log(
      `Total Supply: ${(Number(info.totalSupply) / 1e8).toFixed(2)} MULTI`,
      colors.bright + colors.green,
    );
    log("\nReserve Composition:", colors.yellow);

    let totalValueLocked = 0;
    for (const backing of info.backingTokens) {
      const tokenName =
        backing.tokenInfo.canisterId.toString() === TOKEN_A.toString()
          ? "Token A"
          : backing.tokenInfo.canisterId.toString() === TOKEN_B.toString()
            ? "Token B"
            : backing.tokenInfo.canisterId.toString() === TOKEN_C.toString()
              ? "Token C"
              : "Unknown";

      const reserveAmount = Number(backing.reserveQuantity) / 1e8;
      const backingPerMulti =
        Number(backing.backingUnit) / Number(info.supplyUnit);
      const expectedReserve =
        (Number(info.totalSupply) / 1e8) * backingPerMulti;

      log(`  ${tokenName}:`, colors.blue);
      log(`    Reserve: ${reserveAmount.toFixed(2)} tokens`, colors.blue);
      log(`    Backing: ${backingPerMulti.toFixed(2)} per MULTI`, colors.blue);
      log(
        `    Expected: ${expectedReserve.toFixed(2)} tokens (for current supply)`,
        colors.cyan,
      );

      // Add to total value (simplified - assumes all tokens worth $1)
      totalValueLocked += reserveAmount;
    }

    log(
      `\n💰 Total Value Locked: ${totalValueLocked.toFixed(2)} tokens`,
      colors.bright + colors.magenta,
    );
    log(
      `📈 Collateralization Ratio: ${((totalValueLocked / (Number(info.totalSupply) / 1e8)) * 100).toFixed(1)}%`,
      colors.bright + colors.magenta,
    );
  }
}

// Main execution
async function main() {
  try {
    // Check for init-only flag
    const initOnly = process.argv.includes("--init-only");

    if (!initOnly) {
      log("\n🌟 Multi Token Demo Script", colors.bright + colors.magenta);
      log("This script will demonstrate the Multi token system", colors.yellow);
      log("Watch your frontend to see real-time updates!\n", colors.yellow);
    }

    // Check if backend is available
    try {
      const backend = await multiBackend(minter);
      await backend.isInitialized();
    } catch (error) {
      log(
        '❌ Cannot connect to backend. Please run "yarn local" first.',
        colors.red,
      );
      process.exit(1);
    }

    // Check current state
    const state = await checkSystemState();

    if (!state.initialized) {
      if (!initOnly) {
        log("System not initialized. Initializing now...", colors.yellow);
      }
      await initializeSystem();

      if (initOnly) {
        process.exit(0);
      }
    } else {
      if (initOnly) {
        log("System already initialized", colors.green);
        process.exit(0);
      }
      log(
        `System already initialized with ${(Number(state.totalSupply) / 1e8).toFixed(2)} MULTI in circulation`,
        colors.green,
      );
    }

    // Wait a bit before starting operations
    log("\nStarting demo operations in 3 seconds...", colors.yellow);
    await sleep(3000);

    // Run demo
    await performDemoOperations();

    logSection("✅ Demo Complete!");
    log("Check your frontend to see the final state", colors.green);
    log(
      "The basket composition should now show the reserve balances",
      colors.green,
    );
  } catch (error) {
    console.error("\n❌ Error during demo:", error);
    process.exit(1);
  }
}

// Run if called directly
main().catch((error) => {
  console.error("\n❌ Error during demo:", error);
  process.exit(1);
});
