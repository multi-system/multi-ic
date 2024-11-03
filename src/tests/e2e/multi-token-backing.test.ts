import { describe, expect, test } from "vitest";
import { Principal } from "@dfinity/principal";
import { multiBackend } from "./actor";

describe("Multi Token Backing System", () => {
  const ICP_PRINCIPAL = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
  const ETH_PRINCIPAL = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
  const USD_PRINCIPAL = Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai");

  test.sequential("1. should validate backing configuration", async () => {
    const initialState = await multiBackend.isInitialized();
    if (initialState) {
      console.log("Warning: Canister already initialized");
      return;
    }

    const zeroSupplyConfig = {
      supplyUnit: BigInt(0),
      totalSupply: BigInt(1000),
      backingPairs: [
        {
          tokenInfo: {
            canisterId: ICP_PRINCIPAL,
            token: ICP_PRINCIPAL,
          },
          backingUnit: BigInt(100),
          reserveQuantity: BigInt(0),
        },
      ],
    };
    const zeroSupplyResult = await multiBackend.initialize(zeroSupplyConfig);
    expect(zeroSupplyResult).toEqual({ err: "Supply unit cannot be zero" });

    const zeroUnitsConfig = {
      supplyUnit: BigInt(100),
      totalSupply: BigInt(1000),
      backingPairs: [
        {
          tokenInfo: {
            canisterId: ICP_PRINCIPAL,
            token: ICP_PRINCIPAL,
          },
          backingUnit: BigInt(0),
          reserveQuantity: BigInt(0),
        },
      ],
    };
    const zeroUnitsResult = await multiBackend.initialize(zeroUnitsConfig);
    expect(zeroUnitsResult).toEqual({
      err: "Backing units must be greater than 0",
    });

    const emptyPairsConfig = {
      supplyUnit: BigInt(100),
      totalSupply: BigInt(1000),
      backingPairs: [],
    };
    const emptyPairsResult = await multiBackend.initialize(emptyPairsConfig);
    expect(emptyPairsResult).toEqual({ err: "Backing tokens cannot be empty" });
  });

  test.sequential(
    "2. should initialize with three backing tokens",
    async () => {
      const initialState = await multiBackend.isInitialized();
      if (initialState) {
        console.log("Warning: Canister already initialized");
        return;
      }

      const config = {
        supplyUnit: BigInt(100),
        totalSupply: BigInt(1000),
        backingPairs: [
          {
            tokenInfo: {
              canisterId: ICP_PRINCIPAL,
              token: ICP_PRINCIPAL,
            },
            backingUnit: BigInt(100),
            reserveQuantity: BigInt(0),
          },
          {
            tokenInfo: {
              canisterId: ETH_PRINCIPAL,
              token: ETH_PRINCIPAL,
            },
            backingUnit: BigInt(50),
            reserveQuantity: BigInt(0),
          },
          {
            tokenInfo: {
              canisterId: USD_PRINCIPAL,
              token: USD_PRINCIPAL,
            },
            backingUnit: BigInt(200),
            reserveQuantity: BigInt(0),
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
        expect(token.tokenInfo).toEqual(config.backingPairs[index].tokenInfo);
        expect(token.backingUnit).toEqual(
          config.backingPairs[index].backingUnit,
        );
        expect(token.reserveQuantity).toEqual(BigInt(0));
      });
    },
  );

  test.sequential("3. should prevent double initialization", async () => {
    const result = await multiBackend.initialize({
      supplyUnit: BigInt(100),
      totalSupply: BigInt(1000),
      backingPairs: [
        {
          tokenInfo: {
            canisterId: ICP_PRINCIPAL,
            token: ICP_PRINCIPAL,
          },
          backingUnit: BigInt(100),
          reserveQuantity: BigInt(0),
        },
      ],
    });
    expect(result).toEqual({ err: "Already initialized" });
  });

  test.sequential("4. should handle backing token operations", async () => {
    const tokens = await multiBackend.getBackingTokens();
    if (tokens.length === 0) {
      console.log("Warning: No backing tokens found");
      return;
    }

    expect(tokens[0].tokenInfo.token.toText()).toBe(ICP_PRINCIPAL.toText());
    expect(tokens[0].backingUnit).toBe(BigInt(100));
    expect(tokens[0].reserveQuantity).toBe(BigInt(0));
  });
});
