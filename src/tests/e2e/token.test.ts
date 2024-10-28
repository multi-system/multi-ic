import { expect, test, describe } from "vitest";
import { Principal } from "@dfinity/principal";
import { multi_backend } from "./actor"; // Fixed import path

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
      owner: Principal.fromText("2vxsx-fae"),
      subaccount: [],
    };

    const balance = await multi_backend.icrc1_balance_of(testAccount);
    expect(typeof balance).toBe("bigint");
  });

  test("should handle allowance operations", async () => {
    const testOwner = Principal.fromText("2vxsx-fae");
    const testSpender = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    // Check initial allowance
    const initialAllowance = await multi_backend.icrc2_allowance({
      account: { owner: testOwner, subaccount: [] },
      spender: { owner: testSpender, subaccount: [] },
    });

    expect(initialAllowance.allowance).toBe(0n);

    // Approve an allowance
    const approveResult = await multi_backend.icrc2_approve({
      spender: { owner: testSpender, subaccount: [] },
      amount: 1000n,
      fee: [10_000n],
      memo: [],
      from_subaccount: [],
      expires_at: [],
      created_at_time: [],
      expected_allowance: [],
    });

    expect(approveResult).toEqual({ ok: 0n }); // Changed from Ok to ok
  });

  test("should handle invalid approve requests", async () => {
    const testSpender = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    // Test zero amount (should fail)
    const zeroAmountResult = await multi_backend.icrc2_approve({
      spender: { owner: testSpender, subaccount: [] },
      amount: 0n,
      fee: [10_000n],
      memo: [],
      from_subaccount: [],
      expires_at: [],
      created_at_time: [],
      expected_allowance: [],
    });

    expect(zeroAmountResult).toEqual({ err: "Amount must be greater than 0" }); // Changed from Err to err
  });
});
