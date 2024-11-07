import Principal "mo:base/Principal";

module {
  public type TokenConfig = {
    canisterId : Principal;
    backingUnit : Nat;
  };

  public type InitializeMsg = {
    supplyUnit : Nat;
    backingTokens : [TokenConfig];
  };
};
