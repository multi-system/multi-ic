import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Actor, HttpAgent } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
// @ts-ignore
import { idlFactory as backendIdl } from '../../declarations/multi_backend';
// @ts-ignore
import type { _SERVICE } from '../../declarations/multi_backend';
import { TOKEN_PRICES, getTokenInfo, calculateMultiPrice, preloadTokenMetadata } from '../config/tokenPrices';
import MultiLogo from '../assets/multi_logo.svg';
import { formatAmount, formatMultiPrice, formatUSD } from '../utils/formatters';
import InfoCard from './InfoCard';

const REFRESH_INTERVAL = 3000;
const REFRESH_INDICATOR_MIN_TIME = 500; // Minimum time to show refresh indicator

interface BackingToken {
  tokenInfo: { canisterId: Principal | string };
  backingUnit: bigint;
  reserveQuantity: bigint;
}

interface SystemInfo {
  initialized: boolean;
  totalSupply: bigint;
  supplyUnit: bigint;
  multiToken: { canisterId: Principal | string };
  governanceToken: { canisterId: Principal | string };
  backingTokens: BackingToken[];
}

type PriceDisplay = 'usd' | 'multi';

const BasketDisplay: React.FC = () => {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

  // View controls
  const [priceDisplay, setPriceDisplay] = useState<PriceDisplay>('usd');
  const [multiAmount, setMultiAmount] = useState<string>('1');

  // Refs to track refresh timing
  const refreshStartTime = useRef<number>(0);
  const refreshTimeoutId = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    // Preload token metadata when component mounts
    preloadTokenMetadata();
  }, []);
  
  // Calculate derived values
  const multiPrice = systemInfo
    ? calculateMultiPrice(systemInfo.backingTokens, systemInfo.supplyUnit)
    : 0;

  // Calculate value percentages
  const calculateValuePercentages = useCallback(() => {
    if (!systemInfo) return [];

    let totalValue = 0;
    const tokenValues = systemInfo.backingTokens.map((token) => {
      const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
      const tokenAmount = Number(token.backingUnit) / 1e8;
      const value = tokenAmount * (tokenInfo?.priceUSD || 0);
      totalValue += value;
      return { token, value, tokenInfo };
    });

    return tokenValues.map((tv) => ({
      ...tv,
      percentage: totalValue > 0 ? (tv.value / totalValue) * 100 : 0,
    }));
  }, [systemInfo]);

  const fetchBasketInfo = useCallback(async (isAutoRefresh = false) => {
    try {
      // For auto-refresh, show indicator but don't set loading
      if (isAutoRefresh) {
        refreshStartTime.current = Date.now();
        setRefreshing(true);

        // Clear any existing timeout
        if (refreshTimeoutId.current) {
          clearTimeout(refreshTimeoutId.current);
        }
      } else {
        setLoading(true);
      }

      setError(null);

      const host =
        import.meta.env.VITE_DFX_NETWORK === 'ic' ? 'https://icp-api.io' : 'http://localhost:4943';

      const agent = new HttpAgent({ host });

      if (import.meta.env.VITE_DFX_NETWORK !== 'ic') {
        await agent.fetchRootKey();
      }

      const canisterId =
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND ||
        process.env.CANISTER_ID_MULTI_BACKEND ||
        'bd3sg-teaaa-aaaaa-qaaba-cai';

      const actor = Actor.createActor<_SERVICE>(backendIdl, {
        agent,
        canisterId,
      });

      const result = await actor.getSystemInfo();

      if ('ok' in result) {
        setSystemInfo(result.ok);
        setLastRefresh(new Date());
      } else {
        setError(`Failed to fetch basket information: ${JSON.stringify(result.err)}`);
      }
    } catch (err) {
      console.error('Error fetching basket:', err);
      setError('Error loading basket data');
    } finally {
      if (isAutoRefresh) {
        // Calculate how long the refresh has been showing
        const elapsed = Date.now() - refreshStartTime.current;
        const remaining = Math.max(0, REFRESH_INDICATOR_MIN_TIME - elapsed);

        // Ensure minimum display time for refresh indicator
        refreshTimeoutId.current = setTimeout(() => {
          setRefreshing(false);
        }, remaining);
      } else {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }, []);

  // Initial load
  useEffect(() => {
    fetchBasketInfo(false);
  }, [fetchBasketInfo]);

  // Auto-refresh
  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      fetchBasketInfo(true);
    }, REFRESH_INTERVAL);

    return () => {
      clearInterval(interval);
      if (refreshTimeoutId.current) {
        clearTimeout(refreshTimeoutId.current);
      }
    };
  }, [autoRefresh, fetchBasketInfo]);

  if (loading) {
    return (
      <div className="card">
        <div className="flex items-center justify-center py-12">
          <svg className="animate-spin h-8 w-8 text-white mr-3" viewBox="0 0 24 24">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
              fill="none"
            ></circle>
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            ></path>
          </svg>
          <span className="text-white">Loading basket composition...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="card">
        <div className="text-center py-12">
          <p className="text-red-400">{error}</p>
          <button
            onClick={() => fetchBasketInfo(false)}
            className="mt-4 px-6 py-2 bg-[#586CE1] hover:bg-[#4056C7] text-white rounded-lg transition-colors"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!systemInfo || !systemInfo.initialized) {
    return (
      <div className="card">
        <p className="text-center text-gray-400 py-12">
          The Multi token system is not yet initialized.
        </p>
      </div>
    );
  }

  const valuePercentages = calculateValuePercentages();
  const multiAmountNum = parseFloat(multiAmount) || 0;

  return (
    <div className="space-y-6">
      {/* Main Content */}
      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <img src={MultiLogo} alt="Multi" className="h-10 w-10" />
            <h2 className="text-2xl font-bold text-white">Multi Token Reserve Basket</h2>
          </div>

          <div className="flex items-center gap-4">
            {/* Price Display Toggle */}
            <div className="flex bg-white bg-opacity-10 rounded-lg p-1">
              <button
                onClick={() => setPriceDisplay('usd')}
                className={`px-3 py-2 rounded-md text-sm font-medium transition-all ${
                  priceDisplay === 'usd'
                    ? 'bg-[#586CE1] text-white'
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                USD
              </button>
              <button
                onClick={() => setPriceDisplay('multi')}
                className={`px-3 py-2 rounded-md text-sm font-medium transition-all ${
                  priceDisplay === 'multi'
                    ? 'bg-[#586CE1] text-white'
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                MULTI
              </button>
            </div>

            {/* Refresh Controls */}
            <div
              className="flex items-center gap-2 text-sm min-w-[60px]"
              title={refreshing ? 'Fetching latest data...' : 'Data is up to date'}
            >
              <div
                className={`w-2 h-2 rounded-full transition-colors duration-300 ${
                  refreshing ? 'bg-yellow-400' : 'bg-green-400'
                } ${refreshing && autoRefresh ? 'animate-pulse' : ''}`}
              ></div>
              <span className="text-gray-400 select-none">Live</span>
            </div>

            <label className="flex items-center gap-2 cursor-pointer">
              <span className="text-sm text-gray-400 select-none">Auto-refresh</span>
              <button
                onClick={() => setAutoRefresh(!autoRefresh)}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  autoRefresh ? 'bg-[#586CE1]' : 'bg-gray-600'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    autoRefresh ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </label>

            <button
              onClick={() => fetchBasketInfo(false)}
              disabled={refreshing}
              className={`text-gray-400 hover:text-white transition-colors ${
                refreshing ? 'animate-spin' : ''
              }`}
              title={refreshing ? 'Refreshing...' : 'Refresh now'}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
            </button>
          </div>
        </div>

        {/* System Overview */}
        <div className="flex flex-row gap-4">
          <InfoCard
            label="Total Supply"
            value={formatAmount(systemInfo.totalSupply)}
            unitName="MULTI tokens"
          />

          <InfoCard label="Multi Price" value={formatUSD(multiPrice)} unitName="per Multi token" />

          <InfoCard
            label="Total Value Locked"
            value={formatUSD((Number(systemInfo.totalSupply) / 1e8) * multiPrice)}
            unitName="USD equivalent"
          />

          <InfoCard
            label="Backing Tokens"
            value={String(systemInfo.backingTokens.length)}
            unitName="different assets"
          />
        </div>

        {/* Value Composition Visual */}
        <div className="mb-6">
          <h3 className="text-lg font-semibold text-white mb-4">Portfolio Value Composition</h3>
          <div className="bg-white bg-opacity-5 rounded-lg p-4">
            <div className="flex h-8 rounded-full overflow-hidden mb-4">
              {valuePercentages.map((vp, index) => {
                const style = getTokenStyle(index);
                return (
                  <div
                    key={index}
                    style={{
                      width: `${vp.percentage}%`,
                      ...style.bar,
                    }}
                    className="transition-all duration-1000"
                    title={`${vp.tokenInfo?.symbol}: ${vp.percentage.toFixed(1)}%`}
                  />
                );
              })}
            </div>

            <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
              {valuePercentages.map((vp, index) => {
                const style = getTokenStyle(index);
                return (
                  <div key={index} className="flex items-center gap-2">
                    <div className="w-3 h-3 rounded-full" style={style.badge} />
                    <span className="text-sm text-gray-300">
                      {vp.tokenInfo?.symbol}: {vp.percentage.toFixed(1)}% (
                      {priceDisplay === 'usd' ? formatUSD(vp.value) : formatMultiPrice(vp.value)})
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Redemption Calculator */}
        <div className="mb-6">
          <h3 className="text-lg font-semibold text-white mb-4">Redemption Calculator</h3>
          <div className="bg-white bg-opacity-5 rounded-lg p-4">
            <div className="flex items-center gap-3 mb-4">
              <input
                type="number"
                value={multiAmount}
                onChange={(e) => setMultiAmount(e.target.value)}
                className="w-32 px-3 py-2 rounded-md bg-white bg-opacity-10 text-white border border-white border-opacity-20 focus:outline-none focus:ring-2 focus:ring-[#586CE1]"
                step="0.01"
                min="0"
              />
              <span className="text-gray-300">MULTI tokens can be redeemed for:</span>
              <span className="ml-auto text-lg font-semibold text-white">
                ≈{' '}
                {priceDisplay === 'usd'
                  ? formatUSD(multiAmountNum * multiPrice)
                  : `${multiAmountNum.toFixed(4)} MULTI`}
              </span>
            </div>

            <div className="grid gap-2 pt-3 border-t border-white border-opacity-10">
              {systemInfo.backingTokens.map((token, index) => {
                const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
                const amountPerMulti = Number(token.backingUnit) / Number(systemInfo.supplyUnit);
                const totalAmount = amountPerMulti * multiAmountNum;
                const value = totalAmount * (tokenInfo?.priceUSD || 0);

                return (
                  <div key={index} className="flex justify-between items-center text-sm">
                    <span className="text-gray-300">
                      {tokenInfo?.name || `Token ${index}`} ({tokenInfo?.symbol})
                    </span>
                    <div className="text-right">
                      <span className="font-mono text-white">{totalAmount.toFixed(8)}</span>
                      <span className="text-gray-400 ml-2">
                        ({priceDisplay === 'usd' ? formatUSD(value) : formatMultiPrice(value)})
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Detailed Token Information */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-white">Reserve Token Details</h3>

          <div className="space-y-3">
            {systemInfo.backingTokens.map((token, index) => {
              const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
              const style = getTokenStyle(index);
              const backingPerMulti = Number(token.backingUnit) / Number(systemInfo.supplyUnit);
              const vp = valuePercentages[index];
              const tokenPrice =
                priceDisplay === 'usd'
                  ? formatUSD(tokenInfo?.priceUSD || 0)
                  : formatMultiPrice(tokenInfo?.priceUSD || 0);

              return (
                <div
                  key={index}
                  className="bg-white bg-opacity-5 rounded-lg p-4 hover:bg-opacity-10 transition-colors duration-300"
                >
                  <div className="flex justify-between items-start mb-3">
                    <div className="flex items-center space-x-3">
                      <div
                        className="w-12 h-12 rounded-full flex items-center justify-center"
                        style={style.badge}
                      >
                        <span className="text-white font-semibold">
                          {tokenInfo?.symbol || 'TKN'}
                        </span>
                      </div>
                      <div>
                        <p className="text-white font-medium text-lg">
                          {tokenInfo?.name || `Token ${index}`}
                        </p>
                        <p className="text-xs text-gray-400">
                          {token.tokenInfo.canisterId.toString().slice(0, 10)}...
                        </p>
                        <p className="text-sm text-gray-300 mt-1">{tokenPrice} per token</p>
                      </div>
                    </div>

                    <div className="text-right">
                      <div className="flex items-baseline gap-1">
                        <p className="text-2xl font-bold text-white">{vp.percentage.toFixed(1)}</p>
                        <span className="text-sm text-gray-400">%</span>
                      </div>
                      <p className="text-sm text-gray-400">of portfolio value</p>
                    </div>
                  </div>

                  {/* Progress bar */}
                  <div className="w-full bg-white bg-opacity-10 rounded-full h-2 mb-3 overflow-hidden">
                    <div
                      className="h-2 rounded-full transition-all duration-1000 ease-out"
                      style={{
                        width: `${vp.percentage}%`,
                        ...style.bar,
                      }}
                    />
                  </div>

                  {/* Token Details Grid */}
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                    <div>
                      <p className="text-gray-400">Per MULTI</p>
                      <p className="text-white font-mono">{backingPerMulti.toFixed(8)}</p>
                    </div>
                    <div>
                      <p className="text-gray-400">Backing Units</p>
                      <p className="text-white font-mono">{token.backingUnit.toString()}</p>
                    </div>
                    <div>
                      <p className="text-gray-400">Reserve</p>
                      <p className="text-white font-mono">{formatAmount(token.reserveQuantity)}</p>
                    </div>
                    <div>
                      <p className="text-gray-400">Total Value</p>
                      <p className="text-white">
                        {priceDisplay === 'usd' ? formatUSD(vp.value) : formatMultiPrice(vp.value)}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* System Info Footer */}
      <div className="card">
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-400">Supply Unit</span>
            <span className="text-white font-mono">{systemInfo.supplyUnit.toString()}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">Multi Token</span>
            <span className="text-white font-mono text-xs">
              {systemInfo.multiToken.canisterId.toString()}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">Governance Token</span>
            <span className="text-white font-mono text-xs">
              {systemInfo.governanceToken.canisterId.toString()}
            </span>
          </div>
          <div className="flex justify-between items-center pt-2 border-t border-white border-opacity-10">
            <span className="text-xs text-gray-500">
              Last updated: {lastRefresh.toLocaleTimeString()}
            </span>
            {autoRefresh && (
              <span className="text-xs text-gray-500">
                Auto-refresh: {REFRESH_INTERVAL / 1000}s
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

// Helper function for token styling
const getTokenStyle = (index: number): { badge: React.CSSProperties; bar: React.CSSProperties } => {
  // Create variations of the brand color
  const styles = [
    {
      badge: { background: '#586CE1' },
      bar: { background: 'linear-gradient(to right, #586CE1, #7A8BF0)' },
    },
    {
      badge: { background: 'linear-gradient(to bottom right, #586CE1, #4056C7)' },
      bar: { background: 'linear-gradient(to right, #4056C7, #586CE1)' },
    },
    {
      badge: { background: 'linear-gradient(to bottom right, #7A8BF0, #586CE1)' },
      bar: { background: 'linear-gradient(to right, #7A8BF0, #9AA7F5)' },
    },
  ];
  return styles[index % styles.length];
};

export default BasketDisplay;
