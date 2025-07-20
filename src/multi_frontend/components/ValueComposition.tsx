

export default function ValueComposition({
    valuePercentages
} : {
    valuePercentages: 
}) {

    return (
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
    );
}