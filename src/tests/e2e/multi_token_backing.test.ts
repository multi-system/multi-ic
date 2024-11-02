import { describe, expect, test } from "vitest";
import { Principal } from "@dfinity/principal";
import { multi_backend } from "./actor";

describe("Multi Token Backing System", () => {
  // Our three backing tokens
  const icpPrincipal = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
  const ethPrincipal = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
  const usdPrincipal = Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai");

  test.sequential("1. should validate backing configuration", async () => {
    // First check initial state
    const initialState = await multi_backend.is_initialized();
    if (initialState) {
      console.log("Warning: Canister already initialized");
      return;
    }

    // Test zero supply unit
    const zeroSupplyConfig = {
      supply_unit: BigInt(0),
      total_supply: BigInt(1000),
      backing_pairs: [
        {
          token_info: {
            canister_id: icpPrincipal,
            token: icpPrincipal,
          },
          backing_unit: BigInt(100),
          reserve_quantity: BigInt(0),
        },
      ],
    };
    const zeroSupplyResult = await multi_backend.initialize(zeroSupplyConfig);
    expect(zeroSupplyResult).toEqual({ err: "Supply unit cannot be zero" });

    // Test zero units in backing pair
    const zeroUnitsConfig = {
      supply_unit: BigInt(100),
      total_supply: BigInt(1000),
      backing_pairs: [
        {
          token_info: {
            canister_id: icpPrincipal,
            token: icpPrincipal,
          },
          backing_unit: BigInt(0),
          reserve_quantity: BigInt(0),
        },
      ],
    };
    const zeroUnitsResult = await multi_backend.initialize(zeroUnitsConfig);
    expect(zeroUnitsResult).toEqual({
      err: "Backing units must be greater than 0",
    });

    // Test empty backing pairs
    const emptyPairsConfig = {
      supply_unit: BigInt(100),
      total_supply: BigInt(1000),
      backing_pairs: [],
    };
    const emptyPairsResult = await multi_backend.initialize(emptyPairsConfig);
    expect(emptyPairsResult).toEqual({ err: "Backing tokens cannot be empty" });
  });

  test.sequential(
    "2. should initialize with three backing tokens",
    async () => {
      const initialState = await multi_backend.is_initialized();
      if (initialState) {
        console.log("Warning: Canister already initialized");
        return;
      }

      const config = {
        supply_unit: BigInt(100),
        total_supply: BigInt(1000),
        backing_pairs: [
          {
            token_info: {
              canister_id: icpPrincipal,
              token: icpPrincipal,
            },
            backing_unit: BigInt(100),
            reserve_quantity: BigInt(0),
          },
          {
            token_info: {
              canister_id: ethPrincipal,
              token: ethPrincipal,
            },
            backing_unit: BigInt(50),
            reserve_quantity: BigInt(0),
          },
          {
            token_info: {
              canister_id: usdPrincipal,
              token: usdPrincipal,
            },
            backing_unit: BigInt(200),
            reserve_quantity: BigInt(0),
          },
        ],
      };

      // Initialize
      const result = await multi_backend.initialize(config);
      expect(result).toEqual({ ok: null });

      // Verify initialized state
      const finalState = await multi_backend.is_initialized();
      expect(finalState).toBe(true);

      // Verify backing tokens configuration
      const storedTokens = await multi_backend.get_backing_tokens();
      expect(storedTokens.length).toBe(3);

      // Verify the units configuration but expect empty reserves
      storedTokens.forEach((token, index) => {
        expect(token.token_info).toEqual(
          config.backing_pairs[index].token_info,
        );
        expect(token.backing_unit).toEqual(
          config.backing_pairs[index].backing_unit,
        );
        expect(token.reserve_quantity).toEqual(BigInt(0));
      });
    },
  );

  test.sequential("3. should prevent double initialization", async () => {
    const result = await multi_backend.initialize({
      supply_unit: BigInt(100),
      total_supply: BigInt(1000),
      backing_pairs: [
        {
          token_info: {
            canister_id: icpPrincipal,
            token: icpPrincipal,
          },
          backing_unit: BigInt(100),
          reserve_quantity: BigInt(0),
        },
      ],
    });
    expect(result).toEqual({ err: "Already initialized" });
  });

  test.sequential("4. should handle backing token operations", async () => {
    const tokens = await multi_backend.get_backing_tokens();
    if (tokens.length === 0) {
      console.log("Warning: No backing tokens found");
      return;
    }

    expect(tokens[0].token_info.token.toText()).toBe(icpPrincipal.toText());
    expect(tokens[0].backing_unit).toBe(BigInt(100));
    expect(tokens[0].reserve_quantity).toBe(BigInt(0));
  });
});
