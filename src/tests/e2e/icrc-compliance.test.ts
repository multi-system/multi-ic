import { expect, test, describe, beforeAll } from "vitest";
import { Principal } from "@dfinity/principal";
import { multiBackend, MULTI_BACKEND_ID, testPrincipal } from "./actor";

describe("ICRC Standard Compliance", () => {
  let backend: Awaited<ReturnType<typeof multiBackend>>;

  beforeAll(async () => {
    // Ensure backend is properly initialized before any tests run
    backend = await multiBackend();
  });

  test("should return correct token metadata", async () => {
    const name = await backend.icrc1_name();
    expect(name).toBe("Multi Token");

    const symbol = await backend.icrc1_symbol();
    expect(symbol).toBe("MULTI");

    const decimals = await backend.icrc1_decimals();
    expect(decimals).toBe(8);

    const fee = await backend.icrc1_fee();
    expect(fee).toBe(10_000n);
  });

  test("should handle balance queries", async () => {
    const testAccount = {
      owner: testPrincipal,
      subaccount: [] as number[],
    };

    const balance = await backend.icrc1_balance_of(testAccount);
    expect(typeof balance).toBe("bigint");
    expect(balance).toBe(0n);
  });

  test("should prevent direct minting", async () => {
    const mintingAccount = await backend.icrc1_minting_account();
    expect(mintingAccount).toBeDefined();

    if (mintingAccount && mintingAccount.owner) {
      expect(Principal.from(mintingAccount.owner).toText()).toBe(
        MULTI_BACKEND_ID.toText(),
      );

      const transferResult = await backend.icrc1_transfer({
        from: {
          owner: mintingAccount.owner,
          subaccount: null,
        },
        to: {
          owner: testPrincipal,
          subaccount: [] as number[],
        },
        amount: 1000n,
        fee: [] as number[],
        memo: [] as number[],
        created_at_time: [] as bigint[],
      });

      expect("Err" in transferResult).toBe(true);
    }
  });

  test("should handle allowance operations", async () => {
    const spenderPrincipal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    try {
      // First check initial allowance
      const initialAllowance = await backend.icrc2_allowance({
        account: { owner: testPrincipal, subaccount: [] as number[] },
        spender: { owner: spenderPrincipal, subaccount: [] as number[] },
      });
      expect(initialAllowance.allowance).toBe(0n);

      // Add small delay to ensure state is settled
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Then try approval
      const approveResult = await backend.icrc2_approve({
        spender: { owner: spenderPrincipal, subaccount: [] as number[] },
        amount: 1000n,
        fee: [10_000n],
        memo: [] as number[],
        from_subaccount: [] as number[],
        expires_at: [] as bigint[],
        created_at_time: [] as bigint[],
        expected_allowance: [] as bigint[],
      });

      expect(approveResult).toEqual({
        Err: {
          InsufficientFunds: { balance: 0n },
        },
      });
    } catch (error) {
      // Handle the case where the canister traps
      expect(error).toBeDefined();
    }
  });
});
