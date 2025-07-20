import { Actor, HttpAgent } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
// @ts-ignore
import { idlFactory as tokenIdl } from '../../declarations/token_a'; // They all use the same ICRC-1 interface

// Token price configuration
export type TokenPrice = {
  symbol: string;
  name: string;
  priceUSD: number;
  decimals: number;
  lastUpdated?: string;
};

// Cache for token metadata
const tokenMetadataCache: Record<string, TokenPrice> = {};

// Only hardcode the prices, everything else comes from the canister
const TOKEN_PRICE_MAP: Record<string, number> = {
  // These should match your actual canister IDs
  'by6od-j4aaa-aaaaa-qaadq-cai': 0.85, // Token A
  'avqkn-guaaa-aaaaa-qaaea-cai': 1.2, // Token B
  'asrmz-lmaaa-aaaaa-qaaeq-cai': 3.4, // Token C
};

// ICRC-1 token interface
interface ICRC1Token {
  icrc1_name: () => Promise<string>;
  icrc1_symbol: () => Promise<string>;
  icrc1_decimals: () => Promise<number>;
}

// Query token metadata from the canister
async function fetchTokenMetadata(canisterId: string): Promise<TokenPrice | undefined> {
  // Check cache first
  if (tokenMetadataCache[canisterId]) {
    return tokenMetadataCache[canisterId];
  }

  try {
    const host =
      import.meta.env.VITE_DFX_NETWORK === 'ic' ? 'https://icp-api.io' : 'http://localhost:4943';

    const agent = new HttpAgent({ host });

    if (import.meta.env.VITE_DFX_NETWORK !== 'ic') {
      await agent.fetchRootKey();
    }

    const actor = Actor.createActor<ICRC1Token>(tokenIdl, {
      agent,
      canisterId,
    });

    // Query all metadata in parallel
    const [name, symbol, decimals] = await Promise.all([
      actor.icrc1_name(),
      actor.icrc1_symbol(),
      actor.icrc1_decimals(),
    ]);

    // Get price from our hardcoded map
    const priceUSD = TOKEN_PRICE_MAP[canisterId] || 1.0;

    const tokenInfo: TokenPrice = {
      name,
      symbol,
      decimals,
      priceUSD,
      lastUpdated: new Date().toISOString(),
    };

    // Cache the result
    tokenMetadataCache[canisterId] = tokenInfo;

    return tokenInfo;
  } catch (error) {
    console.error(`Failed to fetch metadata for token ${canisterId}:`, error);

    // Fallback to a default
    return {
      name: `Token ${canisterId.slice(0, 5)}`,
      symbol: 'TKN',
      decimals: 8,
      priceUSD: TOKEN_PRICE_MAP[canisterId] || 1.0,
      lastUpdated: new Date().toISOString(),
    };
  }
}

// Synchronous helper that returns cached data or undefined
export const getTokenInfo = (canisterId: string): TokenPrice | undefined => {
  // First check if we have it cached
  if (tokenMetadataCache[canisterId]) {
    return tokenMetadataCache[canisterId];
  }

  // If not cached, trigger the fetch (but return undefined for now)
  fetchTokenMetadata(canisterId).then((metadata) => {
    if (metadata) {
      // This will update the cache for next time
      console.log(`Fetched metadata for ${canisterId}:`, metadata);
    }
  });

  // Return a temporary placeholder
  return {
    name: 'Loading...',
    symbol: '...',
    decimals: 8,
    priceUSD: TOKEN_PRICE_MAP[canisterId] || 1.0,
    lastUpdated: new Date().toISOString(),
  };
};

// Preload all known tokens
export async function preloadTokenMetadata() {
  const tokenIds = Object.keys(TOKEN_PRICE_MAP);
  await Promise.all(tokenIds.map((id) => fetchTokenMetadata(id)));
}

// Calculate MULTI token price based on backing
export const calculateMultiPrice = (
  backingTokens: Array<{
    tokenInfo: { canisterId: string | { toString(): string } };
    backingUnit: bigint;
  }>,
  supplyUnit: bigint
): number => {
  let totalValue = 0;

  for (const backing of backingTokens) {
    const canisterIdStr =
      typeof backing.tokenInfo.canisterId === 'string'
        ? backing.tokenInfo.canisterId
        : backing.tokenInfo.canisterId.toString();

    const tokenInfo = getTokenInfo(canisterIdStr);
    if (tokenInfo && tokenInfo.priceUSD) {
      // Convert backing units to token amount using the actual decimals
      const tokenAmount = Number(backing.backingUnit) / 10 ** tokenInfo.decimals;
      totalValue += tokenAmount * tokenInfo.priceUSD;
    }
  }

  // Divide by supply unit to get price per MULTI
  return totalValue / (Number(supplyUnit) / 1e8);
};
