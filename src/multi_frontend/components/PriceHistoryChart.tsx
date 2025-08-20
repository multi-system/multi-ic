import React, { useState, useEffect, useMemo, memo } from 'react';
import { Actor, HttpAgent } from '@dfinity/agent';
import {
  LineChart,
  Line,
  Area,
  AreaChart,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { idlFactory as historyIdl } from '../../declarations/multi_history';
import { formatUSD } from '../utils/formatters';
import { Loader } from './Loader';

type TimeRange = '1H' | '1D' | '1W' | '1M' | '1Y';

interface SnapshotData {
  timestamp: bigint;
  prices: Array<[string, bigint]>;
  backing: {
    backingPairs: Array<{
      token: string;
      backingUnit: bigint;
    }>;
    supplyUnit: bigint;
    totalSupply: bigint;
  };
}

interface ChartDataPoint {
  timestamp: number;
  date: string;
  tvl: number;
  [key: string]: number | string; // For individual token values
}

interface TokenInfo {
  canisterId: string;
  symbol: string;
  name: string;
  color: string;
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

const PriceHistoryChart: React.FC<{
  systemInfo: any;
  backingTokens: any[];
}> = ({ systemInfo, backingTokens }) => {
  const [timeRange, setTimeRange] = useState<TimeRange>('1W');
  const [chartData, setChartData] = useState<ChartDataPoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showIndividualTokens, setShowIndividualTokens] = useState(true);

  // Map tokens to consistent colors and symbols
  const tokenInfoMap = useMemo(() => {
    const map: Record<string, TokenInfo> = {};
    backingTokens.forEach((token, index) => {
      const canisterId = token.tokenInfo.canisterId.toString();
      map[canisterId] = {
        canisterId,
        symbol: token.tokenInfo.symbol || `Token${index}`,
        name: token.tokenInfo.name || `Token ${index}`,
        color: COLORS[index % COLORS.length],
      };
    });
    return map;
  }, [backingTokens]);

  // Fetch historical data from the history canister
  const fetchHistoricalData = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const host = 
        import.meta.env.VITE_DFX_NETWORK === 'ic' 
          ? 'https://icp-api.io' 
          : 'http://localhost:4943';

      const agent = new HttpAgent({ host });
      
      if (import.meta.env.VITE_DFX_NETWORK !== 'ic') {
        await agent.fetchRootKey();
      }

      const historyActor = Actor.createActor(historyIdl, {
        agent,
        canisterId: import.meta.env.VITE_CANISTER_ID_MULTI_HISTORY,
      });

      // Calculate time range - FIX: Use BigInt consistently
      const now = BigInt(Date.now()) * BigInt(1000000); // Convert to nanoseconds as BigInt
      let startTime = now;
      
      switch (timeRange) {
        case '1H':
          startTime = now - BigInt(60 * 60 * 1000000000);
          break;
        case '1D':
          startTime = now - BigInt(24 * 60 * 60 * 1000000000);
          break;
        case '1W':
          startTime = now - BigInt(7 * 24 * 60 * 60 * 1000000000);
          break;
        case '1M':
          startTime = now - BigInt(30 * 24 * 60 * 60 * 1000000000);
          break;
        case '1Y':
          startTime = now - BigInt(365 * 24 * 60 * 60 * 1000000000);
          break;
      }

      // Fetch snapshots in time range
      const snapshots = await historyActor.getSnapshotsInTimeRange(
        startTime,  // Already a BigInt
        now,        // Already a BigInt
        [100]       // Max 100 snapshots
      );

      // Process snapshots into chart data
      const processedData: ChartDataPoint[] = snapshots.map((item: any) => {
        const snapshot = item.snapshot;
        const timestamp = Number(snapshot.timestamp) / 1000000; // Convert from nanoseconds to milliseconds
        
        // Create price map from snapshot
        const priceMap: Record<string, number> = {};
        snapshot.prices.forEach(([token, price]: [any, bigint]) => {
          priceMap[token.toString()] = Number(price) / 100000000; // Assuming 8 decimals for price
        });

        // Calculate individual token values and TVL
        let tvl = 0;
        const dataPoint: ChartDataPoint = {
          timestamp,
          date: new Date(timestamp).toLocaleDateString(),
          tvl: 0,
        };

        // Get total supply in MULTI tokens - THIS IS THE KEY FIX
        const totalSupplyMulti = Number(snapshot.backing.totalSupply) / 100000000;

        snapshot.backing.backingPairs.forEach((pair: any) => {
          const tokenId = pair.token.toString();
          const tokenInfo = tokenInfoMap[tokenId];
          if (tokenInfo && priceMap[tokenId]) {
            // Calculate actual reserve quantity based on total supply
            const backingPerMulti = Number(pair.backingUnit) / 100000000;
            const totalReserveQuantity = backingPerMulti * totalSupplyMulti;
            const price = priceMap[tokenId];
            const value = totalReserveQuantity * price;
            
            dataPoint[tokenInfo.symbol] = value;
            tvl += value;
          }
        });

        dataPoint.tvl = tvl;
        return dataPoint;
      });

      // Sort by timestamp
      processedData.sort((a, b) => a.timestamp - b.timestamp);
      
      setChartData(processedData);
    } catch (err) {
      console.error('Error fetching historical data:', err);
      setError('Failed to load historical data');
      
      // Generate mock data for demonstration
      generateMockData();
    } finally {
      setLoading(false);
    }
  };

  // Generate mock data for demonstration
  const generateMockData = () => {
    const now = Date.now();
    const dataPoints = 50;
    const data: ChartDataPoint[] = [];
    
    for (let i = 0; i < dataPoints; i++) {
      const timestamp = now - (dataPoints - i) * 3600000; // Hour intervals
      const baseValue = 100000 + Math.sin(i * 0.2) * 20000;
      
      const point: ChartDataPoint = {
        timestamp,
        date: new Date(timestamp).toLocaleDateString(),
        tvl: 0,
      };
      
      let tvl = 0;
      Object.values(tokenInfoMap).forEach((token, index) => {
        const value = (baseValue / 3) * (1 + Math.sin(i * 0.1 + index) * 0.2);
        point[token.symbol] = value;
        tvl += value;
      });
      
      point.tvl = tvl;
      data.push(point);
    }
    
    setChartData(data);
  };

  // Only fetch when timeRange changes - not on every auto-refresh!
  useEffect(() => {
    fetchHistoricalData();
  }, [timeRange]); // Removed backingTokens dependency to prevent refresh

  // Custom tooltip
  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-gray-900 p-3 rounded-lg border border-gray-700 shadow-xl">
          <p className="text-white font-semibold mb-2">{label}</p>
          <p className="text-green-400 font-bold mb-2">
            TVL: {formatUSD(payload[0]?.payload?.tvl || 0)}
          </p>
          {showIndividualTokens && (
            <div className="space-y-1">
              {Object.values(tokenInfoMap).map((token) => {
                const value = payload[0]?.payload?.[token.symbol];
                if (value) {
                  return (
                    <div key={token.symbol} className="flex justify-between gap-4">
                      <span className="text-gray-400">{token.symbol}:</span>
                      <span className="text-white">{formatUSD(value)}</span>
                    </div>
                  );
                }
                return null;
              })}
            </div>
          )}
        </div>
      );
    }
    return null;
  };

  if (loading) {
    return (
      <div className="bg-white bg-opacity-5 rounded-lg p-8">
        <div className="flex items-center justify-center">
          <Loader size="lg" />
          <span className="ml-4 text-white">Loading historical data...</span>
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
    <div className="space-y-4">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold text-white">Multi Reserve Evolution</h2>
        
        {/* Controls */}
        <div className="flex items-center gap-4">
          {/* Toggle individual tokens */}
          <button
            onClick={() => setShowIndividualTokens(!showIndividualTokens)}
            className="px-3 py-1 text-sm bg-gray-800 hover:bg-gray-700 text-white rounded-lg transition-colors"
          >
            {showIndividualTokens ? 'Hide' : 'Show'} Tokens
          </button>
          
          {/* Time range selector */}
          <div className="flex bg-gray-800 rounded-lg p-1">
            {(['1H', '1D', '1W', '1M', '1Y'] as TimeRange[]).map((range) => (
              <button
                key={range}
                onClick={() => setTimeRange(range)}
                className={`px-3 py-1 text-sm font-medium rounded transition-all ${
                  timeRange === range
                    ? 'bg-[#586CE1] text-white'
                    : 'text-gray-400 hover:text-white'
                }`}
              >
                {range}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Chart */}
      <div className="bg-white bg-opacity-5 rounded-lg p-6">
        <ResponsiveContainer width="100%" height={400}>
          <AreaChart data={chartData}>
            <defs>
              {Object.values(tokenInfoMap).map((token) => (
                <linearGradient key={token.symbol} id={`gradient-${token.symbol}`} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={token.color} stopOpacity={0.3} />
                  <stop offset="95%" stopColor={token.color} stopOpacity={0} />
                </linearGradient>
              ))}
            </defs>
            
            <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
            <XAxis 
              dataKey="date" 
              stroke="#9CA3AF"
              style={{ fontSize: '12px' }}
            />
            <YAxis 
              stroke="#9CA3AF"
              style={{ fontSize: '12px' }}
              tickFormatter={(value) => {
                if (value >= 1000000) {
                  return `$${(value / 1000000).toFixed(1)}M`;
                }
                return `$${(value / 1000).toFixed(0)}k`;
              }}
            />
            <Tooltip content={<CustomTooltip />} />
            
            {/* TVL Line */}
            <Line
              type="monotone"
              dataKey="tvl"
              stroke="#10B981"
              strokeWidth={3}
              dot={false}
              name="Total Value Locked"
            />
            
            {/* Individual token areas */}
            {showIndividualTokens && Object.values(tokenInfoMap).map((token) => (
              <Area
                key={token.symbol}
                type="monotone"
                dataKey={token.symbol}
                stroke={token.color}
                fillOpacity={1}
                fill={`url(#gradient-${token.symbol})`}
                strokeWidth={2}
                name={token.symbol}
              />
            ))}
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Statistics */}
      <div className="grid grid-cols-4 gap-4">
        <div className="bg-white bg-opacity-5 rounded-lg p-4">
          <p className="text-sm text-gray-400">Backing Asset Count</p>
          <p className="text-2xl font-bold text-white">{Object.keys(tokenInfoMap).length}</p>
        </div>
        <div className="bg-white bg-opacity-5 rounded-lg p-4">
          <p className="text-sm text-gray-400">Data Points</p>
          <p className="text-2xl font-bold text-white">{chartData.length}</p>
        </div>
        <div className="bg-white bg-opacity-5 rounded-lg p-4">
          <p className="text-sm text-gray-400">Current TVL</p>
          <p className="text-2xl font-bold text-white">
            {chartData.length > 0 ? formatUSD(chartData[chartData.length - 1].tvl) : '$0'}
          </p>
        </div>
        <div className="bg-white bg-opacity-5 rounded-lg p-4">
          <p className="text-sm text-gray-400">Period Change</p>
          <p className={`text-2xl font-bold ${
            chartData.length > 1 && chartData[chartData.length - 1].tvl > chartData[0].tvl 
              ? 'text-green-400' 
              : 'text-red-400'
          }`}>
            {chartData.length > 1 
              ? `${((chartData[chartData.length - 1].tvl / chartData[0].tvl - 1) * 100).toFixed(2)}%`
              : '0%'}
          </p>
        </div>
      </div>
    </div>
  );
};

export default PriceHistoryChart;