import React, { useState, memo } from 'react';
// @ts-ignore
import { idlFactory as backendIdl } from '../../declarations/multi_backend';
// @ts-ignore
import type { _SERVICE } from '../../declarations/multi_backend';
import { getTokenInfo } from '../config/tokenPrices';
import MultiLogo from '../assets/multi_logo.svg';
import { formatAmount, formatMultiPrice, formatUSD } from '../utils/formatters';
import InfoCard from './InfoCard';
import Section from './Section';
import PriceHistoryChart from './PriceHistoryChart';
import { PriceDisplay, ValuePercentage } from '../utils/types';
import { useSystemInfo } from '../contexts/SystemInfoContext';
import { Loader } from './Loader';
import { IncrementalInput } from './IncrementalInput';

const MemoizedPriceHistoryChart = memo(PriceHistoryChart, (prevProps, nextProps) => {
  return prevProps.backingTokens.length === nextProps.backingTokens.length;
});

const BasketDisplay: React.FC = () => {
  const [priceDisplay, setPriceDisplay] = useState<PriceDisplay>('USD');
  const [multiAmount, setMultiAmount] = useState<string>('1');

  const {
    systemInfo,
    loading,
    error,
    autoRefresh,
    refreshing,
    multiPrice,
    calculateValuePercentages,
    fetchBasketInfo,
    setAutoRefresh,
  } = useSystemInfo();

  if (loading) {
    return (
      <div className="card">
        <div className="flex gap-4 items-center justify-center py-12">
          <Loader size="sm" />
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

  const valuePercentages: ValuePercentage[] = calculateValuePercentages();
  const multiAmountNum = parseFloat(multiAmount) || 0;

  const calculateMultiPrice = () => {
    let totalValue = 0;
    for (const token of systemInfo.backingTokens) {
      const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
      const backingPerMulti = Number(token.backingUnit) / Number(systemInfo.supplyUnit);
      const value = backingPerMulti * (tokenInfo?.priceUSD || 0);
      totalValue += value;
    }
    return totalValue;
  };

  const actualMultiPrice = calculateMultiPrice() || multiPrice;

  const formatValue = (usdValue: number): string => {
    if (priceDisplay === 'USD') {
      return formatUSD(usdValue);
    }
    return formatMultiPrice(usdValue, actualMultiPrice);
  };

  return (
    <div className="space-y-6">
      <div className="flex-col flex gap-6">
        <div className="flex w-full items-center justify-between mb-6">
          <div className="flex item-center gap-4">
            <div className="flex items-center gap-3">
              <h2 className="text-4xl font-bold text-nowrap text-white">
                Multi Token Reserve Basket
              </h2>
            </div>

            <div className="flex bg-white bg-opacity-10 rounded-lg p-1">
              <button
                onClick={() => setPriceDisplay('USD')}
                className={`px-3 py-2 rounded-md text-sm font-medium transition-all ${
                  priceDisplay === 'USD'
                    ? 'bg-[#586CE1] text-white'
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                USD
              </button>
              <button
                onClick={() => setPriceDisplay('MULTI')}
                className={`px-3 py-2 rounded-md text-sm font-medium transition-all ${
                  priceDisplay === 'MULTI'
                    ? 'bg-[#586CE1] text-white'
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                MULTI
              </button>
            </div>
          </div>

          <div className="flex relative z-0 items-center gap-4">
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
                className={`inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  autoRefresh ? 'bg-[#586CE1]' : 'bg-gray-600'
                }`}
              >
                <span
                  className={` inline-flex h-4 w-4 relative rounded-full bg-white transition-transform ${
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
                <g transform="scale(-1, 1) translate(-24, 0)">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </g>
              </svg>
            </button>
          </div>
        </div>

        <div className="flex flex-row gap-4">
          <InfoCard
            label="Total Supply"
            value={formatAmount(systemInfo.totalSupply)}
            unitName="MULTI tokens"
          />

          <InfoCard 
            label="Multi Price" 
            value={formatUSD(actualMultiPrice)} 
            unitName="per Multi token" 
          />

          <InfoCard
            label="Total Value Locked"
            value={formatValue((Number(systemInfo.totalSupply) / 1e8) * actualMultiPrice)}
            unitName={priceDisplay === 'USD' ? 'USD equivalent' : 'MULTI equivalent'}
          />

          <InfoCard
            label="Backing Tokens"
            value={String(systemInfo.backingTokens.length)}
            unitName="different assets"
          />
        </div>

        <MemoizedPriceHistoryChart 
          systemInfo={systemInfo} 
          backingTokens={systemInfo.backingTokens}
        />

        <Section title="Portfolio Value Composition">
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
                    {formatValue(vp.value)})
                  </span>
                </div>
              );
            })}
          </div>
        </Section>

        <Section title="Redemption Calculator">
          <div className="">
            <div className="flex items-center gap-3 mb-4">
              <IncrementalInput
                value={multiAmount}
                onChange={(e) => setMultiAmount(e.target.value)}
                step={0.01}
                min={0}
              />
              <span className="text-gray-300">MULTI tokens can be redeemed for:</span>
              <span className="ml-auto text-lg font-semibold text-white">
                ≈ {formatValue(multiAmountNum * actualMultiPrice)}
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
                        ({formatValue(value)})
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </Section>

        <Section title="Reserve Token Details">
          <div className="space-y-3">
            {systemInfo.backingTokens.map((token, index) => {
              const tokenInfo = getTokenInfo(token.tokenInfo.canisterId.toString());
              const style = getTokenStyle(index);
              const backingPerMulti = Number(token.backingUnit) / Number(systemInfo.supplyUnit);
              const vp = valuePercentages[index];
              const tokenPriceDisplay = priceDisplay === 'USD' 
                ? formatUSD(tokenInfo?.priceUSD || 0)
                : `${((tokenInfo?.priceUSD || 0) / actualMultiPrice).toFixed(6)} MULTI`;

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
                        <p className="text-sm text-gray-300 mt-1">{tokenPriceDisplay} per token</p>
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

                  <div className="w-full bg-white bg-opacity-10 rounded-full h-2 mb-3 overflow-hidden">
                    <div
                      className="h-2 rounded-full transition-all duration-1000 ease-out"
                      style={{
                        width: `${vp.percentage}%`,
                        ...style.bar,
                      }}
                    />
                  </div>

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
                      <p className="text-white">{formatValue(vp.value)}</p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </Section>
      </div>
    </div>
  );
};

const getTokenStyle = (index: number): { badge: React.CSSProperties; bar: React.CSSProperties } => {
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