import { Actor, HttpAgent, Identity } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";
import { execSync } from "child_process";
import fetch from "isomorphic-fetch";
import { defaultIdentity, newIdentity } from "./identity";
import { idlFactory } from "../../declarations/multi_backend/multi_backend.did.js";

// Get dfx port for local development
const dfxPort = execSync("dfx info replica-port", { encoding: "utf-8" }).trim();

// Create base agent
export function createAgent(identity?: Identity) {
  const agent = new HttpAgent({
    identity: identity || defaultIdentity,
    host: `http://127.0.0.1:${dfxPort}`,
    fetch,
  });

  if (process.env.DFX_NETWORK !== "ic") {
    agent.fetchRootKey().catch((err) => {
      console.warn("Unable to fetch root key. Is local replica running?");
      console.error(err);
    });
  }

  return agent;
}

// Helper for funding test accounts
export async function fundTestAccount(
  token: any,
  to: Identity,
  amount: bigint,
) {
  const result = await token.icrc1_transfer({
    to: { owner: to.getPrincipal(), subaccount: [] },
    fee: [],
    memo: [],
    from_subaccount: [],
    created_at_time: [],
    amount,
  });
  if (!("Ok" in result)) {
    throw new Error(`Failed to fund test account: ${JSON.stringify(result)}`);
  }
}

// Get canister ID
export const multiBackendCanister = Principal.fromText(
  execSync(`dfx canister id multi_backend`, { encoding: "utf-8" }).trim(),
);

// Create agent with default identity
const agent = createAgent(defaultIdentity);

// Create the multi_backend actor
export const multiBackend = Actor.createActor(idlFactory, {
  agent,
  canisterId: multiBackendCanister,
});

// Export test identity principal
export const testPrincipal = defaultIdentity.getPrincipal();

// Export identity utilities
export { defaultIdentity, newIdentity };
