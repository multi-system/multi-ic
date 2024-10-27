import { expect, test } from "vitest";
import { Actor, CanisterStatus, HttpAgent } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";
import { multiBackendCanister, multi_backend } from "./actor";

test("should handle a basic greeting", async () => {
  const result1 = await multi_backend.greet("test");
  expect(result1).toBe("Hello, test!");
});

test("Should contain a candid interface", async () => {
  const agent = Actor.agentOf(multi_backend) as HttpAgent;
  const id = Principal.from(multiBackendCanister);

  const canisterStatus = await CanisterStatus.request({
    canisterId: id,
    agent,
    paths: ["time", "controllers", "candid"],
  });

  expect(canisterStatus.get("time")).toBeTruthy();
  expect(Array.isArray(canisterStatus.get("controllers"))).toBeTruthy();
  expect(canisterStatus.get("candid")).toMatchInlineSnapshot(`
    "service : {
      greet: (text) -> (text) query;
    }
    "
  `);
});
