import { Ed25519KeyIdentity } from "@dfinity/identity";

export function newIdentity(): Ed25519KeyIdentity {
  return Ed25519KeyIdentity.generate();
}

export const defaultIdentity = newIdentity();
