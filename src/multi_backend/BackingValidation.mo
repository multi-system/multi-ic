import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Types "./BackingTypes";

module {
  /// Validates backing token configuration including reserve quantities
  public func validateBacking(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.backingUnit == 0) {
        return #err("Backing units must be greater than 0");
      };

      if (pair.reserveQuantity == 0) {
        return #err("Reserve must be greater than 0");
      };

      let tokenPrincipal = Principal.fromActor(pair.tokenInfo.token);
      var isPresent = false;
      for (seenPrincipal in seen.vals()) {
        if (seenPrincipal == tokenPrincipal) {
          isPresent := true;
        };
      };
      if (isPresent) {
        return #err("Duplicate token in backing");
      };
      seen.add(tokenPrincipal);
    };

    #ok(());
  };

  /// Validates structure without checking reserves
  public func validateStructure(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.backingUnit == 0) {
        return #err("Backing units must be greater than 0");
      };

      let tokenPrincipal = Principal.fromActor(pair.tokenInfo.token);
      var isPresent = false;
      for (seenPrincipal in seen.vals()) {
        if (seenPrincipal == tokenPrincipal) {
          isPresent := true;
        };
      };
      if (isPresent) {
        return #err("Duplicate token in backing");
      };
      seen.add(tokenPrincipal);
    };

    #ok(());
  };

  /// Validates complete backing configuration
  public func validateBackingConfig(config : Types.BackingConfig) : Result.Result<(), Text> {
    if (config.supplyUnit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (config.totalSupply % config.supplyUnit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    validateStructure(config.backingPairs);
  };
};
