import APL from "../assets/APL.svg";
import HRM from "../assets/HRM.svg";
import ATH from "../assets/ATH.svg";

export const getTokenIcon = (
  symbol: string | undefined,
): string | undefined => {
  if (!symbol) return undefined;

  const icons: Record<string, string> = {
    APL: APL,
    HRM: HRM,
    ATH: ATH,
  };

  return icons[symbol.toUpperCase()];
};
