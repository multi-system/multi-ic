import Types "Types";

module {
  public type BackingPair = {
    token : Types.Token;
    backingUnit : Nat;
  };
  public type BackingConfig = {
    supplyUnit : Nat;
    totalSupply : Nat;
    backingPairs : [BackingPair];
    multiToken : Types.Token;
  };
  public type BackingState = {
    var hasInitialized : Bool;
    var config : BackingConfig;
  };
};
