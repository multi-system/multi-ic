import Principal "mo:base/Principal";

module {
  public type TokenInfo = {
    canisterId : Principal;
  };

  public type BackingPair = {
    tokenInfo : TokenInfo;
    backingUnit : Nat;
  };

  public type BackingConfig = {
    supplyUnit : Nat;
    totalSupply : Nat;
    backingPairs : [BackingPair];
    multiToken : TokenInfo;
  };

  public type BackingState = {
    var hasInitialized : Bool;
    var config : BackingConfig;
  };
};
