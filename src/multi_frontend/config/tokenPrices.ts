// Token price configuration
// Prices in USD - in production, these would come from an oracle or price feed

export interface TokenPrice {
  symbol: string;
  name: string;
  priceUSD: number;
  decimals: number; // for display formatting
  lastUpdated?: string;
}

// Map canister IDs to token information and prices
export const TOKEN_PRICES: Record<string, TokenPrice> = {
  // Token A
  'bw4dl-smaaa-aaaaa-qaacq-cai': {
    symbol: 'TKA',
    name: 'Token A',
    priceUSD: 0.85,
    decimals: 8,
    lastUpdated: '2025-01-31T10:00:00Z',
  },

  // Token B
  'b77ix-eeaaa-aaaaa-qaada-cai': {
    symbol: 'TKB',
    name: 'Token B',
    priceUSD: 2.4,
    decimals: 8,
    lastUpdated: '2025-01-31T10:00:00Z',
  },

  // Token C
  'by6od-j4aaa-aaaaa-qaadq-cai': {
    symbol: 'TKC',
    name: 'Token C',
    priceUSD: 0.15,
    decimals: 8,
    lastUpdated: '2025-01-31T10:00:00Z',
  },

  // Add more tokens as needed
};

// For testnet - you might want different prices
export const TESTNET_TOKEN_PRICES: Record<string, TokenPrice> = {
  // ... testnet specific prices
};

// Helper to get current prices based on environment
export const getTokenPrices = () => {
  const isTestnet = import.meta.env.VITE_DFX_NETWORK === 'testnet';
  return isTestnet ? TESTNET_TOKEN_PRICES : TOKEN_PRICES;
};

// Helper to get token info
export const getTokenInfo = (canisterId: string): TokenPrice | undefined => {
  const prices = getTokenPrices();
  return prices[canisterId];
};

// Calculate MULTI token price based on backing
export const calculateMultiPrice = (
  backingTokens: Array<{ tokenInfo: { canisterId: string }; backingUnit: bigint }>,
  supplyUnit: bigint
): number => {
  let totalValue = 0;

  for (const backing of backingTokens) {
    const tokenInfo = getTokenInfo(backing.tokenInfo.canisterId.toString());
    if (tokenInfo) {
      // Convert backing units to token amount (assuming 8 decimals)
      const tokenAmount = Number(backing.backingUnit) / 1e8;
      totalValue += tokenAmount * tokenInfo.priceUSD;
    }
  }

  // Divide by supply unit to get price per MULTI
  return totalValue / (Number(supplyUnit) / 1e8);
};
