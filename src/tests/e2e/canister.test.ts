import { expect, test } from "vitest";
import { Actor, CanisterStatus, HttpAgent } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";
import { multiBackendCanister, multi_backend } from "./actor";

test("Should contain the correct ICRC candid interface", async () => {
  const agent = Actor.agentOf(multi_backend) as HttpAgent;
  const id = Principal.from(multiBackendCanister);

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
