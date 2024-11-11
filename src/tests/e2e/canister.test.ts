import { expect, test } from "vitest";
import { CanisterStatus } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";
import { multiBackend, MULTI_BACKEND_ID, createAgent, minter } from "./actor";

test("Should contain the correct ICRC candid interface", async () => {
  const agent = createAgent(minter);
  const id = Principal.from(MULTI_BACKEND_ID);

  const canisterStatus = await CanisterStatus.request({
    canisterId: id,
    agent,
    paths: ["time", "controllers", "candid"],
  });

  expect(canisterStatus.get("time")).toBeTruthy();
  expect(Array.isArray(canisterStatus.get("controllers"))).toBeTruthy();

  const candid = canisterStatus.get("candid") as string;
  expect(candid).toContain("icrc1_name");
  expect(candid).toContain("icrc1_symbol");
  expect(candid).toContain("icrc1_decimals");
  expect(candid).toContain("icrc1_fee");
  expect(candid).toContain("icrc2_approve");
  expect(candid).toContain("icrc2_allowance");
});
