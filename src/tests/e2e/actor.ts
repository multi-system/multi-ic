import { execSync } from "child_process";
import type {
  ActorConfig,
  ActorSubclass,
  Agent,
  HttpAgentOptions,
  Identity,
} from "@dfinity/agent";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";
import { Actor, HttpAgent } from "@dfinity/agent";
import { expect } from "vitest";
import fetch from "isomorphic-fetch";
import { minter, defaultIdentity } from "./identity";

// Import declarations
import {
  _SERVICE as MultiService,
  idlFactory as multiTokenIdl,
} from "../../declarations/multi_backend/multi_backend.did.js";
import {
  _SERVICE as TokenService,
  idlFactory as tokenIdl,
} from "../../declarations/token_a/token_a.did.js";

// Actor creation options interface
export interface CreateActorOptions {
  agent?: Agent;
  agentOptions?: HttpAgentOptions;
  actorOptions?: ActorConfig;
}

// Get dfx port
const dfxPort = execSync("dfx info replica-port", { encoding: "utf-8" }).trim();

// Create base agent
export function createAgent(identity?: Identity) {
  const agent = new HttpAgent({
    identity,
    host: `http://127.0.0.1:${dfxPort}`,
    fetch,
  });

  if (process.env.DFX_NETWORK !== "ic") {
    agent.fetchRootKey().catch((err) => {
      console.warn(
        "Unable to fetch root key. Check to ensure that your local replica is running",
      );
      console.error(err);
    });
  }

  return agent;
}

// Base actor creation
export function createActor<T>(
  canisterId: string | Principal,
  idlFactory: IDL.InterfaceFactory,
  options: CreateActorOptions = {},
): ActorSubclass<T> {
  const agentInstance =
    options.agent || new HttpAgent({ ...options.agentOptions });

  if (options.agent && options.agentOptions) {
    console.warn(
      "Detected both agent and agentOptions passed to createActor. Ignoring agentOptions and proceeding with the provided agent.",
    );
  }

  return Actor.createActor(idlFactory, {
    agent: agentInstance,
    canisterId,
    ...options.actorOptions,
  });
}

// Get canister IDs
function getCanisterId(name: string): Principal {
  const envVar = process.env[`${name.toUpperCase()}_CANISTER_ID`];
  if (envVar) {
    return Principal.fromText(envVar);
  }
  try {
    return Principal.fromText(
      execSync(`dfx canister id ${name}`, { encoding: "utf-8" }).trim(),
    );
  } catch (error) {
    throw new Error(`Failed to get canister ID for ${name}: ${error}`);
  }
}

// Export canister IDs
export const TOKEN_A = getCanisterId("token_a");
export const TOKEN_B = getCanisterId("token_b");
export const TOKEN_C = getCanisterId("token_c");
export const MULTI_BACKEND_ID = getCanisterId("multi_backend");

// Token actor creation functions
export function tokenA(identity?: Identity) {
  return createActor<TokenService>(TOKEN_A, tokenIdl, {
    agent: createAgent(identity),
  });
}

export function tokenB(identity?: Identity) {
  return createActor<TokenService>(TOKEN_B, tokenIdl, {
    agent: createAgent(identity),
  });
}

export function tokenC(identity?: Identity) {
  return createActor<TokenService>(TOKEN_C, tokenIdl, {
    agent: createAgent(identity),
  });
}

// Multi backend actor creation
export function multiBackend(identity?: Identity) {
  return createActor<MultiService>(MULTI_BACKEND_ID, multiTokenIdl, {
    agent: createAgent(identity),
  });
}

// Helper for funding test accounts
export async function fundTestAccount(
  token: ActorSubclass<TokenService>,
  to: Identity,
  amount: bigint,
): Promise<void> {
  const result = await token.icrc1_transfer({
    to: { owner: to.getPrincipal(), subaccount: [] },
    fee: [],
    memo: [],
    from_subaccount: [],
    created_at_time: [],
    amount,
  });
  expect(result).toHaveProperty("Ok");
}

export { minter };
export const testPrincipal = defaultIdentity.getPrincipal();
