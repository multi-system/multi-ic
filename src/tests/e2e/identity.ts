import { Ed25519KeyIdentity } from '@dfinity/identity';
import { Secp256k1KeyIdentity } from '@dfinity/identity-secp256k1';

// This key is not a secret. Only use it for testing!
const MINTER_KEY = `-----BEGIN EC PRIVATE KEY-----
MHQCAQEEICJxApEbuZznKFpV+VKACRK30i6+7u5Z13/DOl18cIC+oAcGBSuBBAAK
oUQDQgAEPas6Iag4TUx+Uop+3NhE6s3FlayFtbwdhRVjvOar0kPTfE/N8N6btRnd
74ly5xXEBNSXiENyxhEuzOZrIWMCNQ==
-----END EC PRIVATE KEY-----`;

// Create minter identity from the private key
export const minter = Secp256k1KeyIdentity.fromPem(MINTER_KEY);

// Randomly generate a new test account each run to ensure test robustness
export function newIdentity(): Ed25519KeyIdentity {
  return Ed25519KeyIdentity.generate();
}

// Default identity for operations that don't need specific permissions
export const defaultIdentity = minter;
