import { describe, expect, test, beforeAll } from "vitest";
import { Principal } from "@dfinity/principal";
import { minter, newIdentity } from "./identity";
import {
  multiBackend,
  tokenA,
  tokenB,
  tokenC,
  TOKEN_A,
  TOKEN_B,
  TOKEN_C,
  MULTI_BACKEND_ID,
  fundTestAccount,
} from "./actor";

async function waitForTokenTransfer(
  token: any,
  recipient: Principal,
  expectedAmount: bigint,
  maxAttempts: number = 10,
): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    const balance = await token.icrc1_balance_of({
      owner: recipient,
      subaccount: [],
    });
    if (balance >= expectedAmount) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

describe("Multi Token Backing System", () => {
  const testIdentity = newIdentity();
  const backend = multiBackend(testIdentity);

  beforeAll(async () => {
    try {
      // Fund test identity with tokens
      await Promise.all([
        fundTestAccount(tokenA(minter), testIdentity, BigInt(1_000_000)),
        fundTestAccount(tokenB(minter), testIdentity, BigInt(1_000_000)),
        fundTestAccount(tokenC(minter), testIdentity, BigInt(1_000_000)),
      ]);

      // Log initial balances
      const [balanceA, balanceB, balanceC] = await Promise.all([
        tokenA(testIdentity).icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
        tokenB(testIdentity).icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
        tokenC(testIdentity).icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
      ]);

      console.log("Test identity balances:", {
        tokenA: balanceA.toString(),
        tokenB: balanceB.toString(),
        tokenC: balanceC.toString(),
      });
    } catch (e) {
      console.error("Error setting up test balances:", e);
      throw e;
    }
  });

  test.sequential(
    "1. should validate backing configuration",
    { timeout: 15000 },
    async () => {
      const initialState = await backend.isInitialized();
      if (initialState) {
        console.log("Warning: Canister already initialized");
        return;
      }

      // Test zero supply unit
      const zeroSupplyConfig = {
        supplyUnit: BigInt(0),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
        ],
      };
      const zeroSupplyResult = await backend.initialize(zeroSupplyConfig);
      expect(zeroSupplyResult).toEqual({
        err: "Supply unit cannot be zero",
      });

      // Test zero backing units
      const zeroUnitsConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(0),
          },
        ],
      };
      const zeroUnitsResult = await backend.initialize(zeroUnitsConfig);
      expect(zeroUnitsResult).toEqual({
        err: "Backing units must be greater than 0",
      });

      // Test empty backing tokens
      const emptyTokensConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [],
      };
      const emptyTokensResult = await backend.initialize(emptyTokensConfig);
      expect(emptyTokensResult).toEqual({
        err: "Backing tokens cannot be empty",
      });

      // Test duplicate tokens
      const duplicateConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(200),
          },
        ],
      };
      const duplicateResult = await backend.initialize(duplicateConfig);
      expect(duplicateResult).toEqual({
        err: "Duplicate token in backing",
      });
    },
  );

  test.sequential(
    "2. should initialize with three backing tokens",
    { timeout: 15000 },
    async () => {
      const initialState = await backend.isInitialized();
      if (initialState) {
        console.log("Warning: Canister already initialized");
        return;
      }

      const config = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: TOKEN_B,
            backingUnit: BigInt(50),
          },
          {
            canisterId: TOKEN_C,
            backingUnit: BigInt(200),
          },
        ],
      };

      const result = await backend.initialize(config);
      expect(result).toEqual({ ok: null });

      const finalState = await backend.isInitialized();
      expect(finalState).toBe(true);

      const storedTokens = await backend.getBackingTokens();
      expect(storedTokens.length).toBe(3);

      storedTokens.forEach((token, index) => {
        expect(token.tokenInfo.canisterId.toText()).toEqual(
          config.backingTokens[index].canisterId.toText(),
        );
        expect(token.backingUnit).toEqual(
          config.backingTokens[index].backingUnit,
        );
        expect(token.reserveQuantity).toEqual(BigInt(0));
      });
    },
  );

  test.sequential(
    "3. should prevent double initialization",
    { timeout: 15000 },
    async () => {
      const result = await backend.initialize({
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
        ],
      });
      expect(result).toEqual({ err: "Already initialized" });
    },
  );

  test.sequential(
    "4. should handle backing token operations",
    { timeout: 15000 },
    async () => {
      const tokens = await backend.getBackingTokens();
      if (tokens.length === 0) {
        console.log("Warning: No backing tokens found");
        return;
      }

      expect(tokens[0].tokenInfo.canisterId.toText()).toBe(TOKEN_A.toText());
      expect(tokens[0].backingUnit).toBe(BigInt(100));
      expect(tokens[0].reserveQuantity).toBe(BigInt(0));

      expect(tokens[1].tokenInfo.canisterId.toText()).toBe(TOKEN_B.toText());
      expect(tokens[1].backingUnit).toBe(BigInt(50));
      expect(tokens[1].reserveQuantity).toBe(BigInt(0));

      expect(tokens[2].tokenInfo.canisterId.toText()).toBe(TOKEN_C.toText());
      expect(tokens[2].backingUnit).toBe(BigInt(200));
      expect(tokens[2].reserveQuantity).toBe(BigInt(0));
    },
  );

  test.sequential(
    "5. should validate issue operations",
    { timeout: 60000 },
    async () => {
      // Calculate amounts
      const issueAmount = BigInt(100);
      const requiredAmountA = BigInt(100);
      const requiredAmountB = BigInt(50);
      const requiredAmountC = BigInt(200);

      // Get fees
      const [feeA, feeB, feeC] = await Promise.all([
        tokenA(testIdentity).icrc1_fee(),
        tokenB(testIdentity).icrc1_fee(),
        tokenC(testIdentity).icrc1_fee(),
      ]);

      console.log("Token fees:", {
        feeA: feeA.toString(),
        feeB: feeB.toString(),
        feeC: feeC.toString(),
      });

      const totalNeededA = requiredAmountA + feeA + feeA; // Additional fee for approval
      const totalNeededB = requiredAmountB + feeB + feeB;
      const totalNeededC = requiredAmountC + feeC + feeC;

      const backend = multiBackend(testIdentity);

      // Process each token in sequence
      for (const { tokenId, amount, name, token } of [
        {
          tokenId: TOKEN_A,
          amount: totalNeededA - feeA, // Subtract one fee since approve takes its own
          name: "Token A",
          token: tokenA(testIdentity),
        },
        {
          tokenId: TOKEN_B,
          amount: totalNeededB - feeB,
          name: "Token B",
          token: tokenB(testIdentity),
        },
        {
          tokenId: TOKEN_C,
          amount: totalNeededC - feeC,
          name: "Token C",
          token: tokenC(testIdentity),
        },
      ]) {
        console.log(`Processing ${name}...`);

        // Add approval before deposit - approve for transfer amount plus fee
        const approveResult = await token.icrc2_approve({
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
          amount: amount + feeA,
          fee: [],
          memo: [],
          from_subaccount: [],
          created_at_time: [],
          expected_allowance: [],
          expires_at: [],
        });
        expect(approveResult).toHaveProperty("Ok");

        // Wait a bit for approval to be processed
        await new Promise((resolve) => setTimeout(resolve, 1000));

        // Use deposit function to transfer tokens and create virtual balance
        const depositResult = await backend.deposit({
          token: tokenId,
          amount,
        });
        expect(depositResult).toEqual({ Success: null });
        console.log(`${name} deposit successful`);

        // Verify virtual balance
        const balance = await backend.getVirtualBalance(
          testIdentity.getPrincipal(),
          tokenId,
        );
        expect(balance).toBe(amount - feeA);
        console.log(`${name} virtual balance: ${balance.toString()}`);
      }

      // Now that all tokens are in virtual ledger, do the issue operation
      const issueResult = await backend.issue({ amount: issueAmount });
      expect(issueResult).toEqual({ Success: null });

      // Verify minting completion
      const finalBalance = await backend.icrc1_balance_of({
        owner: testIdentity.getPrincipal(),
        subaccount: [],
      });
      expect(finalBalance).toBe(issueAmount);

      // Verify supply and reserves
      const finalSupply = await backend.getTotalSupply();
      expect(finalSupply).toBe(issueAmount);

      const finalTokens = await backend.getBackingTokens();
      expect(finalTokens[0].reserveQuantity).toBe(requiredAmountA);
      expect(finalTokens[1].reserveQuantity).toBe(requiredAmountB);
      expect(finalTokens[2].reserveQuantity).toBe(requiredAmountC);
    },
  );

  test.sequential(
    "6. should handle insufficient funds correctly",
    { timeout: 15000 },
    async () => {
      const backend = multiBackend(testIdentity);

      // Store initial state
      const previousTokens = await backend.getBackingTokens();
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);
      const previousSupply = await backend.getTotalSupply();

      // Get virtual balances
      const virtualBalanceA = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      const virtualBalanceB = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_B,
      );
      const virtualBalanceC = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_C,
      );

      console.log("Current virtual balances:", {
        A: virtualBalanceA.toString(),
        B: virtualBalanceB.toString(),
        C: virtualBalanceC.toString(),
      });

      // Request amount that would require more than our virtual balance
      const issueAmount = BigInt(10000);

      // Should return error for insufficient virtual balance
      const result = await backend.issue({ amount: issueAmount });
      expect(result).toHaveProperty("InvalidAmount");
      expect(result.InvalidAmount).toContain("Insufficient");

      // Verify nothing changed
      const tokens = await backend.getBackingTokens();
      tokens.forEach((token, i) => {
        expect(token.reserveQuantity).toBe(previousReserves[i]);
      });
      const currentSupply = await backend.getTotalSupply();
      expect(currentSupply).toBe(previousSupply);

      // Verify virtual balances didn't change
      const finalVirtualBalanceA = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      const finalVirtualBalanceB = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_B,
      );
      const finalVirtualBalanceC = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_C,
      );

      expect(finalVirtualBalanceA).toBe(virtualBalanceA);
      expect(finalVirtualBalanceB).toBe(virtualBalanceB);
      expect(finalVirtualBalanceC).toBe(virtualBalanceC);
    },
  );

  test.sequential(
    "7. should handle transfer failures atomically",
    { timeout: 15000 },
    async () => {
      const backend = multiBackend(testIdentity);

      // Store initial state
      const previousTokens = await backend.getBackingTokens();
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);
      const previousSupply = await backend.getTotalSupply();

      // Get current virtual balances
      const virtualBalanceA = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      const virtualBalanceB = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_B,
      );
      const virtualBalanceC = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_C,
      );

      console.log("Virtual balances before atomic test:", {
        A: virtualBalanceA.toString(),
        B: virtualBalanceB.toString(),
        C: virtualBalanceC.toString(),
      });

      // Try a request that would pass for first two tokens but fail for the last one
      // Token C has backing ratio of 200, so requesting 5100 would need:
      // Token A (ratio 100): 5100 tokens
      // Token B (ratio 50): 2550 tokens
      // Token C (ratio 200): 10200 tokens - should fail
      const atomicAmount = BigInt(5100);

      // Should return error since one token doesn't have enough balance
      const result = await backend.issue({ amount: atomicAmount });
      expect(result).toHaveProperty("InvalidAmount");
      expect(result.InvalidAmount).toContain("Insufficient");

      // Verify nothing changed - this is the key atomicity check
      const tokens = await backend.getBackingTokens();
      tokens.forEach((token, i) => {
        expect(token.reserveQuantity).toBe(previousReserves[i]);
      });
      const currentSupply = await backend.getTotalSupply();
      expect(currentSupply).toBe(previousSupply);

      // Verify virtual balances didn't change
      const finalVirtualBalanceA = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      const finalVirtualBalanceB = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_B,
      );
      const finalVirtualBalanceC = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_C,
      );

      expect(finalVirtualBalanceA).toBe(virtualBalanceA);
      expect(finalVirtualBalanceB).toBe(virtualBalanceB);
      expect(finalVirtualBalanceC).toBe(virtualBalanceC);
    },
  );

  test.sequential(
    "8. should handle token withdrawals correctly",
    { timeout: 60000 },
    async () => {
      const backend = multiBackend(testIdentity);
      const fee = BigInt(10000);
      const testAmount = BigInt(20000);

      // Need to cover:
      // 1. Approval fee
      // 2. Transfer fee
      // 3. The actual amount
      const depositAmount = testAmount + fee + fee;
      const approvalAmount = depositAmount + fee; // Extra fee for the approve operation itself

      // Add approval before deposit
      await tokenA(testIdentity).icrc2_approve({
        spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        amount: approvalAmount,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });

      // Initial setup - deposit tokens
      const depositResult = await backend.deposit({
        token: TOKEN_A,
        amount: depositAmount,
      });
      expect(depositResult).toEqual({ Success: null });

      // Record starting balances
      const startRealBalance = await tokenA(testIdentity).icrc1_balance_of({
        owner: testIdentity.getPrincipal(),
        subaccount: [],
      });

      const startVirtualBalance = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );

      // Perform valid withdrawal
      const withdrawResult = await backend.withdraw({
        token: TOKEN_A,
        amount: testAmount,
      });
      expect(withdrawResult).toEqual({ Success: null });

      // Check real balance updated
      const expectedRealBalance = startRealBalance + (testAmount - fee);
      const currentBalance = await tokenA(testIdentity).icrc1_balance_of({
        owner: testIdentity.getPrincipal(),
        subaccount: [],
      });
      expect(currentBalance).toBe(expectedRealBalance);

      // Check virtual balance decreased
      const endVirtualBalance = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      expect(endVirtualBalance).toBe(startVirtualBalance - testAmount);

      // Test invalid withdrawal - attempt to withdraw more than available
      const invalidWithdrawResult = await backend.withdraw({
        token: TOKEN_A,
        amount: endVirtualBalance + BigInt(1000),
      });

      expect(invalidWithdrawResult).toEqual({
        TransferFailed: {
          token: TOKEN_A,
          error: "Insufficient virtual balance",
        },
      });

      // Verify balances remained unchanged after failed withdrawal
      const finalVirtualBalance = await backend.getVirtualBalance(
        testIdentity.getPrincipal(),
        TOKEN_A,
      );
      expect(finalVirtualBalance).toBe(endVirtualBalance);

      const finalRealBalance = await tokenA(testIdentity).icrc1_balance_of({
        owner: testIdentity.getPrincipal(),
        subaccount: [],
      });
      expect(finalRealBalance).toBe(currentBalance);
    },
  );

  test.sequential(
    "9. should handle multiple concurrent operations safely",
    { timeout: 30000 },
    async () => {
      const identities = [newIdentity(), newIdentity(), newIdentity()];
      const backend = multiBackend(testIdentity);
      const depositAmount = BigInt(100000); // Large enough for multiple operations
      const fee = BigInt(10000);
      const issueAmount = BigInt(100); // Must be multiple of supply unit
      const withdrawAmount = BigInt(20000); // Ensure it's larger than fee (10000)

      // Fund identities - must happen before any test logic
      await Promise.all(
        identities.flatMap((identity) => [
          fundTestAccount(tokenA(minter), identity, BigInt(1_000_000)),
          fundTestAccount(tokenB(minter), identity, BigInt(1_000_000)),
          fundTestAccount(tokenC(minter), identity, BigInt(1_000_000)),
        ]),
      );

      // Test concurrent deposits of the same token
      const sameTokenDeposits = await Promise.all(
        identities.map(async (identity) => {
          // First approve
          await tokenA(identity).icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: depositAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Then deposit the same token simultaneously
          return multiBackend(identity).deposit({
            token: TOKEN_A,
            amount: depositAmount,
          });
        }),
      );

      // Verify all same-token deposits succeeded
      sameTokenDeposits.forEach((result) => {
        expect(result).toEqual({ Success: null });
      });

      // Verify virtual balances for same-token deposits
      await Promise.all(
        identities.map(async (identity) => {
          const virtualBalance = await backend.getVirtualBalance(
            identity.getPrincipal(),
            TOKEN_A,
          );
          expect(virtualBalance).toBe(depositAmount - fee);
        }),
      );

      // Set up virtual balances for remaining tokens
      await Promise.all(
        identities.flatMap((identity) => {
          const tokens = [
            { token: tokenB(identity), tokenId: TOKEN_B },
            { token: tokenC(identity), tokenId: TOKEN_C },
          ];

          return tokens.map(async ({ token, tokenId }) => {
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

            const result = await multiBackend(identity).deposit({
              token: tokenId,
              amount: depositAmount,
            });
            expect(result).toEqual({ Success: null });
          });
        }),
      );

      // Record initial state
      const initialSupply = await backend.getTotalSupply();
      const initialTokens = await backend.getBackingTokens();

      // Execute concurrent issue operations
      const results = await Promise.all(
        identities.map((identity) =>
          multiBackend(identity).issue({ amount: issueAmount }),
        ),
      );

      // Verify all operations succeeded
      results.forEach((result) => {
        expect(result).toEqual({ Success: null });
      });

      // Calculate total issued amount
      const totalIssued = BigInt(identities.length) * issueAmount;

      // Verify final state
      const finalSupply = await backend.getTotalSupply();
      expect(finalSupply).toBe(initialSupply + totalIssued);

      // Verify backing token reserves increased correctly
      const finalTokens = await backend.getBackingTokens();
      finalTokens.forEach((token, i) => {
        const expectedIncrease =
          (totalIssued * token.backingUnit) / BigInt(100);
        expect(token.reserveQuantity).toBe(
          initialTokens[i].reserveQuantity + expectedIncrease,
        );
      });

      // Test concurrent withdrawals of the same token
      const sameTokenWithdrawals = await Promise.all(
        identities.map((identity) =>
          multiBackend(identity).withdraw({
            token: TOKEN_A,
            amount: withdrawAmount, // Now using larger amount that exceeds fee
          }),
        ),
      );

      // Verify all same-token withdrawals succeeded
      sameTokenWithdrawals.forEach((result) => {
        expect(result).toEqual({ Success: null });
      });

      // Verify final virtual balances after same-token withdrawals
      await Promise.all(
        identities.map(async (identity) => {
          const finalVirtualBalance = await backend.getVirtualBalance(
            identity.getPrincipal(),
            TOKEN_A,
          );
          const token = finalTokens.find(
            (t) => t.tokenInfo.canisterId.toText() === TOKEN_A.toText(),
          );
          expect(token).toBeDefined();

          const expectedDeduction =
            (issueAmount * token!.backingUnit) / BigInt(100);
          expect(finalVirtualBalance).toBe(
            depositAmount - expectedDeduction - fee - withdrawAmount,
          );
        }),
      );

      // Test remaining concurrent withdrawals
      const remainingWithdrawals = await Promise.all(
        identities.flatMap((identity) =>
          [TOKEN_B, TOKEN_C].map((tokenId) =>
            multiBackend(identity).withdraw({
              token: tokenId,
              amount: withdrawAmount, // Using same larger amount for consistency
            }),
          ),
        ),
      );

      // Verify all remaining withdrawals succeeded
      remainingWithdrawals.forEach((result) => {
        expect(result).toEqual({ Success: null });
      });

      // Verify final virtual balances for all tokens
      await Promise.all(
        identities.flatMap((identity) =>
          [TOKEN_A, TOKEN_B, TOKEN_C].map(async (tokenId) => {
            const finalVirtualBalance = await backend.getVirtualBalance(
              identity.getPrincipal(),
              tokenId,
            );
            const token = finalTokens.find(
              (t) => t.tokenInfo.canisterId.toText() === tokenId.toText(),
            );
            expect(token).toBeDefined();

            const expectedDeduction =
              (issueAmount * token!.backingUnit) / BigInt(100);
            expect(finalVirtualBalance).toBe(
              depositAmount - expectedDeduction - fee - withdrawAmount,
            );
          }),
        ),
      );
    },
  );

  test.sequential(
    "10. should handle supply unit alignment correctly",
    { timeout: 15000 },
    async () => {
      const backend = multiBackend(testIdentity);
      const fee = BigInt(10000);
      const testAmount = BigInt(20000);

      // First ensure we have enough virtual balance for these tests
      // Transfer tokens which will automatically create virtual balances
      const requiredAmount = BigInt(200); // More than we'll need for tests
      for (const { token, tokenId } of [
        { token: tokenA(testIdentity), tokenId: TOKEN_A },
        { token: tokenB(testIdentity), tokenId: TOKEN_B },
        { token: tokenC(testIdentity), tokenId: TOKEN_C },
      ]) {
        const currentBalance = await backend.getVirtualBalance(
          testIdentity.getPrincipal(),
          tokenId,
        );
        if (currentBalance < requiredAmount) {
          const fee = await token.icrc1_fee();
          const transferAmount = requiredAmount - currentBalance + fee;

          // Add approval before transfer
          await token.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: transferAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Then deposit
          const result = await backend.deposit({
            token: tokenId,
            amount: transferAmount,
          });
          expect(result).toEqual({ Success: null });

          // Wait for virtual balance to sync
          let balanceSynced = false;
          for (let attempt = 0; attempt < 10; attempt++) {
            const balance = await backend.getVirtualBalance(
              testIdentity.getPrincipal(),
              tokenId,
            );
            if (balance >= requiredAmount) {
              balanceSynced = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 1000));
          }
          expect(balanceSynced).toBe(true);
        }
      }

      // Test cases that verify supply unit alignment with backing ratios
      const testCases = [
        { amount: BigInt(99), expected: "multiple of supply unit" }, // Just under supply unit
        { amount: BigInt(101), expected: "multiple of supply unit" }, // Just over supply unit
        { amount: BigInt(150), expected: "multiple of supply unit" }, // Between supply units
      ];

      // Verify misaligned amounts return appropriate errors
      for (const { amount, expected } of testCases) {
        const result = await backend.issue({ amount });
        expect(result).toHaveProperty("InvalidAmount");
        expect(result.InvalidAmount).toContain(expected);
      }

      // Store state before valid operation
      const previousTokens = await backend.getBackingTokens();
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);
      const previousSupply = await backend.getTotalSupply();

      // Verify a valid aligned amount works
      const validAmount = BigInt(100);
      const validResult = await backend.issue({ amount: validAmount });
      expect(validResult).toEqual({ Success: null });

      // Verify state changed correctly for valid amount
      const tokens = await backend.getBackingTokens();
      const currentSupply = await backend.getTotalSupply();
      expect(currentSupply).toBe(previousSupply + validAmount);

      // Verify each token's reserve increased by the correct amount
      tokens.forEach((token, i) => {
        const backingUnit = previousTokens[i].backingUnit;
        const expectedIncrease = (validAmount * backingUnit) / BigInt(100); // supplyUnit is 100
        expect(token.reserveQuantity).toBe(
          previousReserves[i] + expectedIncrease,
        );
      });
    },
  );
});
