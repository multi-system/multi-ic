import { Actor, HttpAgent } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
// @ts-ignore
import { idlFactory as tokenIdl } from '../../declarations/token_a';
// @ts-ignore
import { idlFactory as historyIdl } from '../../declarations/multi_history';

// Token price configuration
export type TokenPrice = {
  symbol: string;
  name: string;
  priceUSD: number;
  decimals: number;
  lastUpdated?: string;
};

// Cache for token metadata and prices
const tokenMetadataCache: Record<string, TokenPrice> = {};
let latestPricesCache: Record<string, number> = {};
let lastPriceFetch = 0;
const PRICE_CACHE_DURATION = 60000; // 1 minute cache

// ICRC-1 token interface
interface ICRC1Token {
  icrc1_name: () => Promise<string>;
  icrc1_symbol: () => Promise<string>;
  icrc1_decimals: () => Promise<number>;
}

// Fetch latest prices from history canister
async function fetchLatestPrices(): Promise<Record<string, number>> {
  // Check cache
  if (
    Date.now() - lastPriceFetch < PRICE_CACHE_DURATION &&
    Object.keys(latestPricesCache).length > 0
  ) {
    return latestPricesCache;
  }

  try {
    const host =
      import.meta.env.VITE_DFX_NETWORK === 'ic' ? 'https://icp-api.io' : 'http://localhost:4943';

    const agent = new HttpAgent({ host });

    if (import.meta.env.VITE_DFX_NETWORK !== 'ic') {
      await agent.fetchRootKey();
    }

    // Connect to history canister
    const historyActor = Actor.createActor(historyIdl, {
      agent,
      canisterId: import.meta.env.VITE_CANISTER_ID_MULTI_HISTORY,
    });

    // Get latest snapshot
    const latestSnapshot = await historyActor.getLatest();

    if (latestSnapshot && latestSnapshot.length > 0) {
      const snapshot = latestSnapshot[0];
      const prices: Record<string, number> = {};

      // Convert prices from snapshot to our format
      // Prices are stored as [Principal, nat] tuples
      snapshot.prices.forEach(([token, price]: [any, bigint]) => {
        const tokenId = token.toString();
        // Assuming prices are stored with 8 decimals in the canister
        prices[tokenId] = Number(price) / 100000000;
      });

      latestPricesCache = prices;
      lastPriceFetch = Date.now();

      console.log('Fetched latest prices from history canister:', prices);
      return prices;
    }

    // Fallback to default prices if no snapshot exists
    console.warn('No snapshot found in history canister, using fallback prices');
    return {
      'by6od-j4aaa-aaaaa-qaadq-cai': 0.85,
      'avqkn-guaaa-aaaaa-qaaea-cai': 1.2,
      'asrmz-lmaaa-aaaaa-qaaeq-cai': 3.4,
    };
  } catch (error) {
    console.error('Failed to fetch prices from history canister:', error);

    // Fallback prices
    return {
      'by6od-j4aaa-aaaaa-qaadq-cai': 0.85,
      'avqkn-guaaa-aaaaa-qaaea-cai': 1.2,
      'asrmz-lmaaa-aaaaa-qaaeq-cai': 3.4,
    };
  }
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

    // Get price from history canister
    const prices = await fetchLatestPrices();
    const priceUSD = prices[canisterId] || 1.0;

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

    // Get price from history canister even if metadata fails
    const prices = await fetchLatestPrices();

    // Fallback to a default with price from history
    return {
      name: `Token ${canisterId.slice(0, 5)}`,
      symbol: 'TKN',
      decimals: 8,
      priceUSD: prices[canisterId] || 1.0,
      lastUpdated: new Date().toISOString(),
    };
  }
}

// Synchronous helper that returns cached data or triggers async fetch
export const getTokenInfo = (canisterId: string): TokenPrice | undefined => {
  // First check if we have it cached
  if (tokenMetadataCache[canisterId]) {
    // Update price from latest snapshot if cache is stale
    if (Date.now() - lastPriceFetch > PRICE_CACHE_DURATION) {
      fetchLatestPrices().then((prices) => {
        if (tokenMetadataCache[canisterId] && prices[canisterId]) {
          tokenMetadataCache[canisterId].priceUSD = prices[canisterId];
          tokenMetadataCache[canisterId].lastUpdated = new Date().toISOString();
        }
      });
    }
    return tokenMetadataCache[canisterId];
  }

  // If not cached, trigger the fetch (but return cached price if available)
  fetchTokenMetadata(canisterId).then((metadata) => {
    if (metadata) {
      console.log(`Fetched metadata for ${canisterId}:`, metadata);
    }
  });

  // Return last known price from cache to prevent price jumps during refresh
  const cachedPrice = latestPricesCache[canisterId];
  return {
    name: 'Loading...',
    symbol: '...',
    decimals: 8,
    priceUSD: cachedPrice || 1.0,
    lastUpdated: new Date().toISOString(),
  };
};

// Preload all tokens from the latest snapshot
export async function preloadTokenMetadata() {
  try {
    // First get all prices from history canister
    const prices = await fetchLatestPrices();
    const tokenIds = Object.keys(prices);

    // Then fetch metadata for all tokens
    await Promise.all(tokenIds.map((id) => fetchTokenMetadata(id)));

    console.log('Preloaded metadata for all tokens from history canister');
  } catch (error) {
    console.error('Failed to preload token metadata:', error);
  }
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

// Function to record a new snapshot (to be called periodically)
export async function recordPriceSnapshot(
  prices: Record<string, number>,
  approvedTokens: string[],
  backingConfig: any
): Promise<void> {
  try {
    const host =
      import.meta.env.VITE_DFX_NETWORK === 'ic' ? 'https://icp-api.io' : 'http://localhost:4943';

    const agent = new HttpAgent({ host });

    if (import.meta.env.VITE_DFX_NETWORK !== 'ic') {
      await agent.fetchRootKey();
    }

    const historyActor = Actor.createActor(historyIdl, {
      agent,
      canisterId: import.meta.env.VITE_CANISTER_ID_MULTI_HISTORY,
    });

    // Convert prices to the format expected by the canister
    const priceEntries = Object.entries(prices).map(([tokenId, price]) => [
      Principal.fromText(tokenId),
      BigInt(Math.floor(price * 100000000)), // Convert to 8 decimals
    ]);

    const approvedPrincipals = approvedTokens.map((t) => Principal.fromText(t));

    await historyActor.recordSnapshot(priceEntries, approvedPrincipals, backingConfig);

    console.log('Successfully recorded price snapshot');
  } catch (error) {
    console.error('Failed to record price snapshot:', error);
  }
}
