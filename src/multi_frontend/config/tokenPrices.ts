import { Actor, HttpAgent } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
// @ts-ignore
import { idlFactory as tokenIdl } from '../../declarations/token_a';
// @ts-ignore
import { idlFactory as historyIdl } from '../../declarations/multi_history';

export type TokenPrice = {
  symbol: string;
  name: string;
  priceUSD: number;
  decimals: number;
  lastUpdated?: string;
};

const tokenMetadataCache: Record<string, TokenPrice> = {};
let latestPricesCache: Record<string, number> = {};
let lastPriceFetch = 0;
const PRICE_CACHE_DURATION = 60000;

const loadingTokens = new Set<string>();
const tokenListeners = new Map<string, Set<() => void>>();

interface ICRC1Token {
  icrc1_name: () => Promise<string>;
  icrc1_symbol: () => Promise<string>;
  icrc1_decimals: () => Promise<number>;
}

function notifyTokenListeners(canisterId: string) {
  const listeners = tokenListeners.get(canisterId);
  if (listeners) {
    listeners.forEach((listener) => listener());
  }
}

export function subscribeToToken(canisterId: string, listener: () => void): () => void {
  if (!tokenListeners.has(canisterId)) {
    tokenListeners.set(canisterId, new Set());
  }
  tokenListeners.get(canisterId)!.add(listener);

  return () => {
    const listeners = tokenListeners.get(canisterId);
    if (listeners) {
      listeners.delete(listener);
      if (listeners.size === 0) {
        tokenListeners.delete(canisterId);
      }
    }
  };
}

async function fetchLatestPrices(): Promise<Record<string, number>> {
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

    const historyActor = Actor.createActor(historyIdl, {
      agent,
      canisterId: import.meta.env.VITE_CANISTER_ID_MULTI_HISTORY,
    });

    const latestSnapshot = await historyActor.getLatest();

    if (latestSnapshot && latestSnapshot.length > 0) {
      const snapshot = latestSnapshot[0];
      const prices: Record<string, number> = {};

      snapshot.prices.forEach(([token, price]: [any, bigint]) => {
        const tokenId = token.toString();
        prices[tokenId] = Number(price) / 100000000;
      });

      latestPricesCache = prices;
      lastPriceFetch = Date.now();
      return prices;
    }

    return {};
  } catch (error) {
    console.error('Failed to fetch prices from history canister:', error);
    return {};
  }
}

async function fetchTokenMetadata(canisterId: string): Promise<TokenPrice | undefined> {
  if (tokenMetadataCache[canisterId]) {
    return tokenMetadataCache[canisterId];
  }

  if (loadingTokens.has(canisterId)) {
    return undefined;
  }

  loadingTokens.add(canisterId);

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

    const [name, symbol, decimals] = await Promise.all([
      actor.icrc1_name(),
      actor.icrc1_symbol(),
      actor.icrc1_decimals(),
    ]);

    const prices = await fetchLatestPrices();
    const priceUSD = prices[canisterId] || 0;

    const tokenInfo: TokenPrice = {
      name,
      symbol,
      decimals,
      priceUSD,
      lastUpdated: new Date().toISOString(),
    };

    tokenMetadataCache[canisterId] = tokenInfo;
    loadingTokens.delete(canisterId);
    notifyTokenListeners(canisterId);

    return tokenInfo;
  } catch (error) {
    console.error(`Failed to fetch metadata for token ${canisterId}:`, error);
    loadingTokens.delete(canisterId);
    return undefined;
  }
}

export const getTokenInfo = (canisterId: string): TokenPrice | undefined => {
  if (tokenMetadataCache[canisterId]) {
    return tokenMetadataCache[canisterId];
  }

  if (!loadingTokens.has(canisterId)) {
    fetchTokenMetadata(canisterId);
  }

  return undefined;
};

export async function preloadTokenMetadata() {
  try {
    const prices = await fetchLatestPrices();
    const tokenIds = Object.keys(prices);
    await Promise.all(tokenIds.map((id) => fetchTokenMetadata(id)));
  } catch (error) {
    console.error('Failed to preload token metadata:', error);
  }
}

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
    if (tokenInfo) {
      const tokenAmount = Number(backing.backingUnit) / 10 ** tokenInfo.decimals;
      totalValue += tokenAmount * tokenInfo.priceUSD;
    }
  }

  return supplyUnit > 0n ? totalValue / (Number(supplyUnit) / 1e8) : 0;
};

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

    const priceEntries = Object.entries(prices).map(([tokenId, price]) => [
      Principal.fromText(tokenId),
      BigInt(Math.floor(price * 100000000)),
    ]);

    const approvedPrincipals = approvedTokens.map((t) => Principal.fromText(t));

    await historyActor.recordSnapshot(priceEntries, approvedPrincipals, backingConfig);
  } catch (error) {
    console.error('Failed to record price snapshot:', error);
  }
}
