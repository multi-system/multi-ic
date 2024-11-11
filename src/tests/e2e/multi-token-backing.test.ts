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

describe("Multi Token Backing System", () => {
  const testIdentity = newIdentity();
  const backend = multiBackend(testIdentity);

  beforeAll(async () => {
    try {
      await Promise.all([
        fundTestAccount(tokenA(minter), testIdentity, BigInt(1_000_000)),
        fundTestAccount(tokenB(minter), testIdentity, BigInt(1_000_000)),
        fundTestAccount(tokenC(minter), testIdentity, BigInt(1_000_000)),
      ]);

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

      // Test with ICP principal (non-ICRC2 token)
      const invalidTokenResult = await backend.initialize({
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai"),
            backingUnit: BigInt(100),
          },
        ],
      });
      expect(invalidTokenResult).toEqual({
        err: "Not a valid ICRC2 token",
      });

      // Test with malformed principal
      const malformedConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: Principal.fromText("aaaaa-aa"), // Invalid canister ID
            backingUnit: BigInt(100),
          },
        ],
      };
      const malformedResult = await backend.initialize(malformedConfig);
      expect(malformedResult).toEqual({
        err: "Not a valid ICRC2 token",
      });

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

  async function approveToken(token: any, amount: bigint) {
    const result = await token.icrc2_approve({
      amount,
      spender: {
        owner: MULTI_BACKEND_ID,
        subaccount: [],
      },
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expires_at: [],
      expected_allowance: [],
    });
    expect(result).toHaveProperty("Ok");
  }

  test.sequential(
    "5. should validate issue operations",
    { timeout: 30000 },
    async () => {
      // Verify initial supply is 0
      const initialSupply = await backend.getTotalSupply();
      expect(initialSupply).toBe(BigInt(0));

      // Verify initial reserves are all 0
      const initialTokens = await backend.getBackingTokens();
      initialTokens.forEach((token) => {
        expect(token.reserveQuantity).toBe(BigInt(0));
      });

      // Test invalid amount (not multiple of supply unit)
      const invalidAmount = await backend.issue({ amount: BigInt(99) });
      expect(invalidAmount).toEqual({
        InvalidAmount: "Amount must be multiple of supply unit",
      });

      // Calculate required backing amounts for 1 supply unit worth of tokens
      const issueAmount = BigInt(100); // We're issuing 100 tokens
      const requiredAmountA = BigInt(100); // 100 tokens of A per supply unit
      const requiredAmountB = BigInt(50); // 50 tokens of B per supply unit
      const requiredAmountC = BigInt(200); // 200 tokens of C per supply unit

      // Get fees for each token
      const feeA = await tokenA(testIdentity).icrc1_fee();
      const feeB = await tokenB(testIdentity).icrc1_fee();
      const feeC = await tokenC(testIdentity).icrc1_fee();

      // Do approvals with correct amounts
      await approveToken(tokenA(testIdentity), requiredAmountA + BigInt(feeA));
      await approveToken(tokenB(testIdentity), requiredAmountB + BigInt(feeB));
      await approveToken(tokenC(testIdentity), requiredAmountC + BigInt(feeC));

      // Add delay to ensure approvals are processed
      await new Promise((resolve) => setTimeout(resolve, 2000));

      // Verify approvals before proceeding
      const [allowanceA, allowanceB, allowanceC] = await Promise.all([
        tokenA(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
        tokenB(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
        tokenC(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
      ]);

      // Verify allowances are set correctly (including fees)
      expect(allowanceA.allowance).toBe(requiredAmountA + BigInt(feeA));
      expect(allowanceB.allowance).toBe(requiredAmountB + BigInt(feeB));
      expect(allowanceC.allowance).toBe(requiredAmountC + BigInt(feeC));

      // Test successful issue
      const successResult = await backend.issue({ amount: issueAmount });
      expect(successResult).toHaveProperty("Success");

      // Add short delay before verifying final state
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Verify reserves were updated - should match the base amounts without fees
      const tokensAfter = await backend.getBackingTokens();
      expect(tokensAfter[0].reserveQuantity).toBe(requiredAmountA);
      expect(tokensAfter[1].reserveQuantity).toBe(requiredAmountB);
      expect(tokensAfter[2].reserveQuantity).toBe(requiredAmountC);

      // Verify minted balance
      const balance = await backend.icrc1_balance_of({
        owner: testIdentity.getPrincipal(),
        subaccount: [],
      });
      expect(balance).toBe(BigInt(100));

      // Verify final supply
      const finalSupply = await backend.getTotalSupply();
      expect(finalSupply).toBe(BigInt(100));
    },
  );

  test.sequential(
    "6. should handle partial approvals correctly",
    { timeout: 15000 },
    async () => {
      // Store initial state
      const previousTokens = await backend.getBackingTokens();
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);
      const previousSupply = await backend.getTotalSupply();

      const issueAmount = BigInt(100);

      // Only approve A and B, not C
      const feeA = await tokenA(testIdentity).icrc1_fee();
      const feeB = await tokenB(testIdentity).icrc1_fee();

      await Promise.all([
        approveToken(tokenA(testIdentity), BigInt(100) + BigInt(feeA)),
        approveToken(tokenB(testIdentity), BigInt(50) + BigInt(feeB)),
      ]);
      // Deliberately skip approving token C

      // Should fail because not all tokens are approved
      const result = await backend.issue({ amount: issueAmount });
      expect(result).toHaveProperty("InvalidAmount");
      expect(result.InvalidAmount).toContain(
        "Insufficient allowance for token",
      );

      // Verify nothing changed
      const tokens = await backend.getBackingTokens();
      tokens.forEach((token, i) => {
        expect(token.reserveQuantity).toBe(previousReserves[i]);
      });
      const currentSupply = await backend.getTotalSupply();
      expect(currentSupply).toBe(previousSupply);

      // Verify final allowance state
      const afterAllowances = await Promise.all([
        tokenA(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
        tokenB(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
        tokenC(testIdentity).icrc2_allowance({
          account: { owner: testIdentity.getPrincipal(), subaccount: [] },
          spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        }),
      ]);

      expect(afterAllowances[0].allowance).toBeGreaterThan(BigInt(0));
      expect(afterAllowances[1].allowance).toBeGreaterThan(BigInt(0));
      expect(afterAllowances[2].allowance).toBe(BigInt(0));
    },
  );

  test.sequential(
    "7. should handle transfer failures atomically",
    { timeout: 15000 },
    async () => {
      // Store initial state
      const previousTokens = await backend.getBackingTokens();
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);
      const previousSupply = await backend.getTotalSupply();

      // Try to issue amount larger than our balance
      const largeAmount = BigInt(1000000);

      await Promise.all([
        approveToken(tokenA(testIdentity), largeAmount * BigInt(100)),
        approveToken(tokenB(testIdentity), largeAmount * BigInt(50)),
        approveToken(tokenC(testIdentity), largeAmount * BigInt(200)),
      ]);

      // Should fail due to insufficient balance
      const result = await backend.issue({ amount: largeAmount });
      expect(result).toHaveProperty("InvalidAmount");
      expect(result.InvalidAmount).toContain("Transfer failed");

      // Verify nothing changed
      const tokens = await backend.getBackingTokens();
      tokens.forEach((token, i) => {
        expect(token.reserveQuantity).toBe(previousReserves[i]);
      });
      const currentSupply = await backend.getTotalSupply();
      expect(currentSupply).toBe(previousSupply);
    },
  );
});
