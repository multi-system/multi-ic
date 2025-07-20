const formatAmount = (amount: bigint, decimals: number = 8): string => {
  const divisor = BigInt(10 ** decimals);
  const whole = amount / divisor;
  const remainder = amount % divisor;

  if (remainder === 0n) {
    return whole.toString();
  }

  const decimal = remainder.toString().padStart(decimals, '0');
  // Remove trailing zeros
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

const formatMultiPrice = (usdPrice: number, multiPrice = 0): string => {
  if (multiPrice === 0) return '0 MULTI';
  const priceInMulti = usdPrice / multiPrice;
  return `${priceInMulti.toFixed(4)} MULTI`;
};

export { formatAmount, formatUSD, formatMultiPrice };
