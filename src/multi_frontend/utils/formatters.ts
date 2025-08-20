const formatAmount = (amount: bigint, decimals: number = 8): string => {
  const divisor = BigInt(10 ** decimals);
  const whole = amount / divisor;
  const remainder = amount % divisor;

  if (remainder === 0n) {
    return whole.toString();
  }

  const decimal = remainder.toString().padStart(decimals, '0');
  const trimmedDecimal = decimal.replace(/0+$/, '');
  return trimmedDecimal ? `${whole}.${trimmedDecimal}` : whole.toString();
};

const formatUSD = (amount: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format(amount);
};

const formatMultiPrice = (usdValue: number, multiPriceInUSD: number): string => {
  if (!multiPriceInUSD || multiPriceInUSD === 0) return '0.0000 MULTI';

  const valueInMulti = usdValue / multiPriceInUSD;

  if (valueInMulti < 0.0001) {
    return '<0.0001 MULTI';
  }

  if (valueInMulti < 1) {
    return `${valueInMulti.toFixed(6)} MULTI`;
  }

  if (valueInMulti < 1000) {
    return `${valueInMulti.toFixed(4)} MULTI`;
  }

  return `${valueInMulti.toFixed(2)} MULTI`;
};

export { formatAmount, formatUSD, formatMultiPrice };
