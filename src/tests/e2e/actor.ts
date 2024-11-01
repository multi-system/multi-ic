import { Actor, HttpAgent } from "@dfinity/agent";
import { Ed25519KeyIdentity } from "@dfinity/identity";
import fetch from "isomorphic-fetch";
import canisterIds from "../../../.dfx/local/canister_ids.json";
import { idlFactory } from "../../declarations/multi_backend/multi_backend.did.js";

// Create a test identity
const testIdentity = Ed25519KeyIdentity.generate();

export const createActor = async (
  canisterId: string,
  options?: {
    agentOptions?: {
      host?: string;
      identity?: Ed25519KeyIdentity;
    };
    actorOptions?: { agent?: HttpAgent };
  },
) => {
  const agent = new HttpAgent({
    ...options?.agentOptions,
    identity: testIdentity,
  });

  await agent.fetchRootKey();

  return Actor.createActor(idlFactory, {
    agent,
    canisterId,
    ...options?.actorOptions,
  });
};

export const multiBackendCanister = canisterIds.multi_backend.local;
export const multi_backend = await createActor(multiBackendCanister, {
  agentOptions: { host: "http://127.0.0.1:4943", fetch },
});

// Export the test identity so tests can access the principal if needed
export const testPrincipal = testIdentity.getPrincipal();
