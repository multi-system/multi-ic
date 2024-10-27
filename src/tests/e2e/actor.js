import { Actor, HttpAgent } from "@dfinity/agent";
import fetch from "isomorphic-fetch";
import canisterIds from "../../../.dfx/local/canister_ids.json";
import { idlFactory } from "../../declarations/multi_backend/multi_backend.did.js";

export const createActor = async (canisterId, options) => {
  const agent = new HttpAgent({ ...options?.agentOptions });
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
