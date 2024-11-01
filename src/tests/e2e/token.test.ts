import { expect, test, describe } from "vitest";
import { Principal } from "@dfinity/principal";
import { multi_backend, testPrincipal } from "./actor";

describe("ICRC Token", () => {
  test("should return correct token metadata", async () => {
    const name = await multi_backend.icrc1_name();
    expect(name).toBe("Multi Token");

    const symbol = await multi_backend.icrc1_symbol();
    expect(symbol).toBe("MULTI");

    const decimals = await multi_backend.icrc1_decimals();
    expect(decimals).toBe(8);

    const fee = await multi_backend.icrc1_fee();
    expect(fee).toBe(10_000n);
  });

  test("should handle balance queries", async () => {
    const testAccount = {
      owner: testPrincipal,
      subaccount: [],
    };

    const balance = await multi_backend.icrc1_balance_of(testAccount);
    expect(typeof balance).toBe("bigint");
  });

  test("should handle allowance operations", async () => {
    const spenderPrincipal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    // Check initial allowance
    const initialAllowance = await multi_backend.icrc2_allowance({
      account: { owner: testPrincipal, subaccount: [] },
      spender: { owner: spenderPrincipal, subaccount: [] },
    });
    expect(initialAllowance.allowance).toBe(0n);

    // Attempt approval (will fail until tokens are issued)
    const approveResult = await multi_backend.icrc2_approve({
      spender: { owner: spenderPrincipal, subaccount: [] },
      amount: 1000n,
      fee: [10_000n],
      memo: [],
      from_subaccount: [],
      expires_at: [],
      created_at_time: [],
      expected_allowance: [],
    });

    // Expect insufficient funds until proper issuance is implemented
    expect(approveResult).toEqual({
      Err: {
        InsufficientFunds: { balance: 0n },
      },
    });
  });
});
