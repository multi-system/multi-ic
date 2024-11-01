import { describe, expect, test } from "vitest";
import { Principal } from "@dfinity/principal";
import { multi_backend } from "./actor";

describe("Multi Token System", () => {
  // Our three backing tokens
  const icpPrincipal = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
  const ethPrincipal = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
  const usdPrincipal = Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai");

  test.sequential("1. should validate backing configuration", async () => {
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
          units: BigInt(100),
          reserve: BigInt(0),
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
          units: BigInt(0),
          reserve: BigInt(0),
        },
      ],
    };
    const zeroUnitsResult = await multi_backend.initialize(zeroUnitsConfig);
    expect(zeroUnitsResult).toEqual({
      err: "Backing units must be greater than 0",
    }); // Updated to match core validation

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
      const config = {
        supply_unit: BigInt(100),
        total_supply: BigInt(1000),
        backing_pairs: [
          {
            token_info: {
              canister_id: icpPrincipal,
              token: icpPrincipal,
            },
            units: BigInt(100), // 100 units of ICP per supply unit
            reserve: BigInt(0), // Initially empty reserve
          },
          {
            token_info: {
              canister_id: ethPrincipal,
              token: ethPrincipal,
            },
            units: BigInt(50), // 50 units of ETH per supply unit
            reserve: BigInt(0), // Initially empty reserve
          },
          {
            token_info: {
              canister_id: usdPrincipal,
              token: usdPrincipal,
            },
            units: BigInt(200), // 200 units of USD per supply unit
            reserve: BigInt(0), // Initially empty reserve
          },
        ],
      };

      // Verify not initialized yet
      const initialState = await multi_backend.is_initialized();
      expect(initialState).toBe(false);

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
        expect(token.units).toEqual(config.backing_pairs[index].units);
        expect(token.reserve).toEqual(BigInt(0)); // All reserves should start at 0
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
          units: BigInt(100),
          reserve: BigInt(0),
        },
      ],
    });
    expect(result).toEqual({ err: "Already initialized" });
  });

  test.sequential("4. should handle backing token operations", async () => {
    // First verify the token is properly initialized but reserves are empty
    const tokens = await multi_backend.get_backing_tokens();
    expect(tokens.length).toBe(3);

    // Verify configuration but with empty reserves
    expect(tokens[0].token_info.token.toText()).toBe(icpPrincipal.toText());
    expect(tokens[0].units).toBe(BigInt(100)); // Configured units
    expect(tokens[0].reserve).toBe(BigInt(0)); // Empty reserve

    // TODO: Add tests for issue and redeem operations
    // These would be the operations that actually build up reserves
  });
});
