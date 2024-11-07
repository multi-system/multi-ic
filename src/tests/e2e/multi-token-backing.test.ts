import { describe, expect, test } from "vitest";
import { Principal } from "@dfinity/principal";
import { multiBackend } from "./actor";
import { execSync } from "child_process";

describe("Multi Token Backing System", () => {
  // Get actual deployed token principals
  const TOKEN_A = Principal.fromText(
    execSync(`dfx canister id token_a`, { encoding: "utf-8" }).trim(),
  );
  const TOKEN_B = Principal.fromText(
    execSync(`dfx canister id token_b`, { encoding: "utf-8" }).trim(),
  );
  const TOKEN_C = Principal.fromText(
    execSync(`dfx canister id token_c`, { encoding: "utf-8" }).trim(),
  );

  test.sequential(
    "1. should validate backing configuration",
    { timeout: 15000 },
    async () => {
      const initialState = await multiBackend.isInitialized();
      if (initialState) {
        console.log("Warning: Canister already initialized");
        return;
      }

      // Test with ICP principal (non-ICRC2 token)
      const invalidTokenResult = await multiBackend.initialize({
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
      const malformedResult = await multiBackend.initialize(malformedConfig);
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
      const zeroSupplyResult = await multiBackend.initialize(zeroSupplyConfig);
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
      const zeroUnitsResult = await multiBackend.initialize(zeroUnitsConfig);
      expect(zeroUnitsResult).toEqual({
        err: "Backing units must be greater than 0",
      });

      // Test empty backing tokens
      const emptyTokensConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [],
      };
      const emptyTokensResult =
        await multiBackend.initialize(emptyTokensConfig);
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
      const duplicateResult = await multiBackend.initialize(duplicateConfig);
      expect(duplicateResult).toEqual({
        err: "Duplicate token in backing",
      });
    },
  );

  test.sequential(
    "2. should initialize with three backing tokens",
    { timeout: 15000 },
    async () => {
      const initialState = await multiBackend.isInitialized();
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

      const result = await multiBackend.initialize(config);
      expect(result).toEqual({ ok: null });

      const finalState = await multiBackend.isInitialized();
      expect(finalState).toBe(true);

      const storedTokens = await multiBackend.getBackingTokens();
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
      const result = await multiBackend.initialize({
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
      const tokens = await multiBackend.getBackingTokens();
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
});
