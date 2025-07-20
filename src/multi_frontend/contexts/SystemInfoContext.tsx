import React, { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react';
import { HttpAgent, Actor } from '@dfinity/agent';
// Import your backend IDL and types
import { calculateMultiPrice, getTokenInfo, preloadTokenMetadata } from '../config/tokenPrices';
import { SystemInfo } from '../utils/types';
// @ts-ignore
import type { _SERVICE } from '../../declarations/multi_backend';
import { idlFactory as backendIdl } from '../../declarations/multi_backend';
import { REFRESH_INDICATOR_MIN_TIME, REFRESH_INTERVAL } from '../utils/constants';

type SystemInfoContextType = {
  systemInfo: SystemInfo | null;
  loading: boolean;
  error: string | null;
  autoRefresh: boolean;
  refreshing: boolean;
  lastRefresh: Date;
  multiPrice: number;
  calculateValuePercentages: () => any[];
  fetchBasketInfo: (isAutoRefresh?: boolean) => Promise<void>;
  setAutoRefresh: (value: boolean) => void;
};

const SystemInfoContext = createContext<SystemInfoContextType | undefined>(undefined);

export const SystemInfoProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

  const refreshStartTime = useRef<number>(0);
  const refreshTimeoutId = useRef<NodeJS.Timeout | null>(null);

  // Example: preload any token metadata
  useEffect(() => {
    preloadTokenMetadata();
  }, []);

  const multiPrice = systemInfo
    ? calculateMultiPrice(systemInfo.backingTokens, systemInfo.supplyUnit)
    : 0;

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
      if (isAutoRefresh) {
        refreshStartTime.current = Date.now();
        setRefreshing(true);
        if (refreshTimeoutId.current) clearTimeout(refreshTimeoutId.current);
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

      const actor = Actor.createActor<_SERVICE>(backendIdl, { agent, canisterId });

      const result = await actor.getSystemInfo();

      if ('ok' in result) {
        setSystemInfo(result.ok);
        setLastRefresh(new Date());
      } else {
        setError(`Failed to fetch basket info: ${JSON.stringify(result.err)}`);
      }
    } catch (err) {
      console.error(err);
      setError('Error loading basket data');
    } finally {
      if (isAutoRefresh) {
        const elapsed = Date.now() - refreshStartTime.current;
        const remaining = Math.max(0, REFRESH_INDICATOR_MIN_TIME - elapsed);
        refreshTimeoutId.current = setTimeout(() => {
          setRefreshing(false);
        }, remaining);
      } else {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }, []);

  useEffect(() => {
    fetchBasketInfo(false);
  }, [fetchBasketInfo]);

  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      fetchBasketInfo(true);
    }, REFRESH_INTERVAL);

    return () => {
      clearInterval(interval);
      if (refreshTimeoutId.current) clearTimeout(refreshTimeoutId.current);
    };
  }, [autoRefresh, fetchBasketInfo]);

  const value: SystemInfoContextType = {
    systemInfo,
    loading,
    error,
    autoRefresh,
    refreshing,
    lastRefresh,
    multiPrice,
    calculateValuePercentages,
    fetchBasketInfo,
    setAutoRefresh,
  };

  return <SystemInfoContext.Provider value={value}>{children}</SystemInfoContext.Provider>;
};

export const useSystemInfo = () => {
  const context = useContext(SystemInfoContext);
  if (context === undefined) {
    throw new Error('useSystemInfo must be used within a SystemInfoProvider');
  }
  return context;
};
