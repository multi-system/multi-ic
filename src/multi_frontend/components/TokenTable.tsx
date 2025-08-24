import React, { useState, useEffect, useMemo } from 'react';
import { formatUSD } from '../utils/formatters';
import { Loader } from './Loader';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faCaretUp, faCaretDown } from '@fortawesome/free-solid-svg-icons';

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
  const [loading, setLoading] = useState(true);
  const [tokens, setTokens] = useState<TokenInfo[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [sortConfig, setSortConfig] = useState<{
    key: SortKey;
    direction: SortDirection;
  }>({ key: 'portfolioShare', direction: 'desc' }); // default sort

  const tokenInfoMap = useMemo(() => {
    return backingTokens.map((token, index) => ({
      canisterId: token.tokenInfo.canisterId.toString(),
      symbol: token.tokenInfo.symbol || `Token${index}`,
      name: token.tokenInfo.name || `Token ${index}`,
      color: COLORS[index % COLORS.length],
      price: Math.random() * 100,
      marketCap: Math.random() * 1_000_000_000,
      volume: Math.random() * 100_000_000,
      supply: Math.random() * 100_000_000,
      change1h: (Math.random() - 0.5) * 2,
      change24h: (Math.random() - 0.5) * 10,
      change7d: (Math.random() - 0.5) * 20,
    }));
  }, [backingTokens]);

  useEffect(() => {
    setLoading(true);
    setTimeout(() => {
      const totalMarketCap = tokenInfoMap.reduce((sum, t) => sum + t.marketCap, 0);
      const withShares = tokenInfoMap.map((t) => ({
        ...t,
        portfolioShare: (t.marketCap / totalMarketCap) * 100,
      }));
      setTokens(withShares);
      setLoading(false);
    }, 1000);
  }, [tokenInfoMap]);

  const sortedTokens = [...tokens].sort((a, b) => {
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

  if (loading) {
    return (
      <div className="bg-white bg-opacity-5 rounded-lg p-8">
        <div className="flex items-center justify-center">
          <Loader size="lg" />
          <span className="ml-4 text-white">Loading token data...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white bg-opacity-5 rounded-lg p-8">
        <p className="text-red-400 text-center">{error}</p>
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
              className="px-4 py-3 text-left cursor-pointer"
              onClick={() => requestSort('name')}
            >
              Name {renderSortIcon('name', 'right')}
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('price')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('price', 'left')} Price
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('change1h')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change1h', 'left')} 1h %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('change24h')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change24h', 'left')} 24h %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('change7d')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('change7d', 'left')} 7d %
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('marketCap')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('marketCap', 'left')} Market Cap
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('volume')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('volume', 'left')} Volume (24h)
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
              onClick={() => requestSort('supply')}
            >
              <span className="flex items-center justify-end">
                {renderSortIcon('supply', 'left')} Circulating Supply
              </span>
            </th>
            <th
              className="px-4 py-3 text-right cursor-pointer"
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
              key={token.symbol}
              className="border-b border-gray-700 hover:bg-gray-700/40"
            >
              <td className="px-4 py-3">{idx + 1}</td>
              <td className="px-4 py-3 flex items-center gap-2">
                <div
                  className="w-5 h-5 rounded-full"
                  style={{ backgroundColor: token.color }}
                />
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
