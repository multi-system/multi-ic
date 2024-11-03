import { expect, test, describe } from "vitest";
import { Principal } from "@dfinity/principal";
import { multiBackend, testPrincipal } from "./actor";

describe("ICRC Standard Compliance", () => {
  test("should return correct token metadata", async () => {
    const name = await multiBackend.icrc1_name();
    expect(name).toBe("Multi Token");

    const symbol = await multiBackend.icrc1_symbol();
    expect(symbol).toBe("MULTI");

    const decimals = await multiBackend.icrc1_decimals();
    expect(decimals).toBe(8);

    const fee = await multiBackend.icrc1_fee();
    expect(fee).toBe(10_000n);
  });

  test("should handle balance queries", async () => {
    const testAccount = {
      owner: testPrincipal,
      subaccount: [],
    };

    const balance = await multiBackend.icrc1_balance_of(testAccount);
    expect(typeof balance).toBe("bigint");
    expect(balance).toBe(0n);
  });

  test("should prevent direct minting", async () => {
    const mintingAccount = await multiBackend.icrc1_minting_account();
    expect(mintingAccount).toBeDefined();

    if (mintingAccount && mintingAccount.owner) {
      expect(Principal.from(mintingAccount.owner).toText()).toBe(
        multiBackend.principal.toText(),
      );

      const transferResult = await multiBackend.icrc1_transfer({
        from: {
          owner: mintingAccount.owner,
          subaccount: null,
        },
        to: {
          owner: testPrincipal,
          subaccount: [],
        },
        amount: 1000n,
        fee: [],
        memo: [],
        created_at_time: [],
      });

      expect("Err" in transferResult).toBe(true);
    }
  });

  test("should handle allowance operations", async () => {
    const spenderPrincipal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    const initialAllowance = await multiBackend.icrc2_allowance({
      account: { owner: testPrincipal, subaccount: [] },
      spender: { owner: spenderPrincipal, subaccount: [] },
    });
    expect(initialAllowance.allowance).toBe(0n);

    const approveResult = await multiBackend.icrc2_approve({
      spender: { owner: spenderPrincipal, subaccount: [] },
      amount: 1000n,
      fee: [10_000n],
      memo: [],
      from_subaccount: [],
      expires_at: [],
      created_at_time: [],
      expected_allowance: [],
    });

    expect(approveResult).toEqual({
      Err: {
        InsufficientFunds: { balance: 0n },
      },
    });
  });
});
