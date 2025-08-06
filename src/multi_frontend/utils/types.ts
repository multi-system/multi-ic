import { Principal } from '@dfinity/principal';
import { TokenPrice } from '../config/tokenPrices';

export type BackingToken = {
  tokenInfo: { canisterId: Principal | string };
  backingUnit: bigint;
  reserveQuantity: bigint;
};

export type SystemInfo = {
  initialized: boolean;
  totalSupply: bigint;
  supplyUnit: bigint;
  multiToken: { canisterId: Principal | string };
  governanceToken: { canisterId: Principal | string };
  backingTokens: BackingToken[];
};

export type ValuePercentage = {
  percentage: number;
  token: BackingToken;
  value: number;
  tokenInfo: TokenPrice | undefined;
};

export type TokenBalance = {
  canisterId: string;
  name: string;
  symbol: string;
  walletBalance: bigint;
  systemBalance: bigint;
  decimals: number;
};

export type PriceDisplay = 'USD' | 'MULTI';
