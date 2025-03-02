import Principal "mo:base/Principal";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Types "Types";

module {
  public type BalanceMap = StableHashMap.StableHashMap<Types.Token, Nat>;
  public type AccountMap = StableHashMap.StableHashMap<Types.Account, BalanceMap>;
};
