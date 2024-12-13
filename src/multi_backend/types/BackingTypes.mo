import Principal "mo:base/Principal";

module {
  /// Information about a backing token
  public type TokenInfo = {
    canisterId : Principal;
  };

  /// Represents a backing token and its configuration
  public type BackingPair = {
    tokenInfo : TokenInfo;
    backingUnit : Nat;
    reserveQuantity : Nat;
  };

  /// Overall configuration for backing tokens
  public type BackingConfig = {
    supplyUnit : Nat;
    totalSupply : Nat;
    backingPairs : [BackingPair];
  };
};
