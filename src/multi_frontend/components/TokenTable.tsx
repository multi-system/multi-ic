import React, { useState, useEffect, useMemo } from 'react';
import { formatUSD } from '../utils/formatters';
import { Loader } from './Loader';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faCaretUp, faCaretDown } from '@fortawesome/free-solid-svg-icons';
import { getTokenInfo, subscribeToToken } from '../config/tokenPrices';
import { getTokenIcon } from '../utils/tokenIcons';

interface TokenInfo {
  canisterId: string;
  symbol: string;
  name: string;
  color: string;
  price: number;
  marketCap: number;
  volume: number;
  supply: number;
  change1h: number;
  change24h: number;
  change7d: number;
  portfolioShare?: number;
}

const COLORS = [
  '#586CE1',
  '#627EEA',
  '#2E7CEE',
  '#7A8BF0',
  '#9AA7F5',
  '#4056C7',
  '#B8C1F5',
];

type SortKey = keyof TokenInfo;
type SortDirection = 'asc' | 'desc';

const TokenTable: React.FC<{
  systemInfo: any;
  backingTokens: any[];
}> = ({ systemInfo, backingTokens }) => {
  const [tokens, setTokens] = useState<TokenInfo[]>([]);
  const [sortConfig, setSortConfig] = useState<{
    key: SortKey;
    direction: SortDirection;
  }>({ key: 'portfolioShare', direction: 'desc' });
  const [updateCounter, forceUpdate] = useState(0);

  useEffect(() => {
    const unsubscribes: (() => void)[] = [];
    
    backingTokens.forEach((token) => {
      const canisterId = token.tokenInfo.canisterId.toString();
      const unsubscribe = subscribeToToken(canisterId, () => {
        forceUpdate(prev => prev + 1);
      });
      unsubscribes.push(unsubscribe);
    });

    return () => {
      unsubscribes.forEach(unsub => unsub());
    };
  }, [backingTokens]);

  const allDataLoaded = useMemo(() => {
    return backingTokens.every(token => {
      const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
      return tokenInfo !== undefined;
    });
  }, [backingTokens, updateCounter]);

  const generatedTokenData = useMemo(() => {
    if (!allDataLoaded) return [];

    const hashCode = (str: string) => {
      let hash = 0;
      for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
      }
      return Math.abs(hash);
    };

    return backingTokens.map((token, index) => {
      const canisterId = token.tokenInfo.canisterId.toString();
      const seed = hashCode(canisterId);
      
      const seededRandom = (min: number, max: number, offset: number) => {
        const x = Math.sin(seed + offset) * 10000;
        return min + (x - Math.floor(x)) * (max - min);
      };

      const tokenInfo = getTokenInfo(canisterId);

      return {
        canisterId,
        symbol: tokenInfo!.symbol,
        name: tokenInfo!.name,
        color: COLORS[index % COLORS.length],
        price: tokenInfo!.priceUSD,
        marketCap: seededRandom(100_000_000, 1_000_000_000, 2),
        volume: seededRandom(10_000_000, 100_000_000, 3),
        supply: seededRandom(10_000_000, 100_000_000, 4),
        change1h: seededRandom(-2, 2, 5),
        change24h: seededRandom(-10, 10, 6),
        change7d: seededRandom(-20, 20, 7),
      };
    });
  }, [backingTokens, allDataLoaded, updateCounter]);

  useEffect(() => {
    if (!allDataLoaded) return;
    
    let totalValue = 0;
    const tokensWithValues = backingTokens.map((token) => {
      const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
      const backingPerMulti = Number(token.backingUnit) / Number(systemInfo.supplyUnit);
      const value = backingPerMulti * (tokenInfo!.priceUSD || 0);
      totalValue += value;
      return value;
    });

    const withShares = generatedTokenData.map((t, index) => ({
      ...t,
      portfolioShare: totalValue > 0 ? (tokensWithValues[index] / totalValue) * 100 : 0,
    }));
    
    setTokens(withShares);
  }, [generatedTokenData, backingTokens, systemInfo, allDataLoaded]);

  const sortedTokens = useMemo(() => {
    return [...tokens].sort((a, b) => {
      const aValue = a[sortConfig.key];
      const bValue = b[sortConfig.key];

      if (aValue == null) return 1;
      if (bValue == null) return -1;

      if (typeof aValue === 'number' && typeof bValue === 'number') {
        return sortConfig.direction === 'asc' ? aValue - bValue : bValue - aValue;
      }

      return sortConfig.direction === 'asc'
        ? String(aValue).localeCompare(String(bValue))
        : String(bValue).localeCompare(String(aValue));
    });
  }, [tokens, sortConfig]);

  const requestSort = (key: SortKey) => {
    let direction: SortDirection = 'asc';
    if (sortConfig.key === key && sortConfig.direction === 'asc') {
      direction = 'desc';
    }
    setSortConfig({ key, direction });
  };

  const renderSortIcon = (key: SortKey, align: 'left' | 'right') => {
    if (sortConfig.key !== key) return null;
    const icon = sortConfig.direction === 'asc' ? faCaretUp : faCaretDown;
    return (
      <FontAwesomeIcon
        icon={icon}
        className={`text-gray-400 ${align === 'left' ? 'mr-1' : 'ml-1'}`}
        size="sm"
      />
    );
  };

  if (!allDataLoaded) {
    return (
      <div className="bg-white bg-opacity-5 rounded-lg p-8">
        <div className="flex items-center justify-center">
          <Loader size="lg" />
          <span className="ml-4 text-white">Loading token data...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white bg-opacity-5 rounded-lg p-6 overflow-x-auto">
      <table className="min-w-full text-sm text-gray-300">
        <thead className="bg-gray-800 text-gray-400 uppercase text-xs">
          <tr>
            <th className="px-4 py-3 text-left">#</th>
            <th
              className="px-4 py-3 text-left cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('name')}
            >
              Name {renderSortIcon('name', 'right')}
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('price')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('price', 'left')} Price
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('change1h')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change1h', 'left')} 1h %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('change24h')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change24h', 'left')} 24h %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('change7d')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change7d', 'left')} 7d %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('marketCap')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('marketCap', 'left')} Market Cap
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('volume')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('volume', 'left')} Volume (24h)
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('supply')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('supply', 'left')} Circulating Supply
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer hover:text-gray-200 transition-colors"
              onClick={() => requestSort('portfolioShare')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('portfolioShare', 'left')} % of Portfolio
              </span>
            </th>
          </tr>
        </thead>
        <tbody>
          {sortedTokens.map((token, idx) => (
            <tr
              key={token.canisterId}
              className="border-b border-gray-700 hover:bg-gray-700/40 transition-colors"
            >
              <td className="px-4 py-3">{idx + 1}</td>
              <td className="px-4 py-3 flex items-center gap-2">
                {(() => {
                  const icon = getTokenIcon(token.symbol);
                  return icon ? (
                    <img src={icon} alt={token.symbol} className="w-5 h-5" />
                  ) : (
                    <div
                      className="w-5 h-5 rounded-full flex-shrink-0"
                      style={{ backgroundColor: token.color }}
                    />
                  );
                })()}
                <span className="font-medium text-white">{token.name}</span>
                <span className="text-gray-400 text-xs">{token.symbol}</span>
              </td>
              <td className="px-4 py-3 text-right">{formatUSD(token.price)}</td>
              <td
                className={`px-4 py-3 text-right ${
                  token.change1h >= 0 ? 'text-green-400' : 'text-red-400'
                }`}
              >
                {token.change1h.toFixed(2)}%
              </td>
              <td
                className={`px-4 py-3 text-right ${
                  token.change24h >= 0 ? 'text-green-400' : 'text-red-400'
                }`}
              >
                {token.change24h.toFixed(2)}%
              </td>
              <td
                className={`px-4 py-3 text-right ${
                  token.change7d >= 0 ? 'text-green-400' : 'text-red-400'
                }`}
              >
                {token.change7d.toFixed(2)}%
              </td>
              <td className="px-4 py-3 text-right">{formatUSD(token.marketCap)}</td>
              <td className="px-4 py-3 text-right">{formatUSD(token.volume)}</td>
              <td className="px-4 py-3 text-right">
                {token.supply.toFixed(2)} {token.symbol}
              </td>
              <td className="px-4 py-3 text-right">
                {token.portfolioShare?.toFixed(2)}%
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default TokenTable;