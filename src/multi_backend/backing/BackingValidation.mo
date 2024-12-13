import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Types "../types/BackingTypes";

module {
  /// Validates backing token configuration
  public func validateStructure(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.backingUnit == 0) {
        return #err("Backing units must be greater than 0");
      };

      var isPresent = false;
      for (seenPrincipal in seen.vals()) {
        if (Principal.equal(seenPrincipal, pair.tokenInfo.canisterId)) {
          isPresent := true;
        };
      };
      if (isPresent) {
        return #err("Duplicate token in backing");
      };
      seen.add(pair.tokenInfo.canisterId);
    };

    #ok(());
  };

  /// Validates complete backing configuration
  public func validateConfig(config : Types.BackingConfig) : Result.Result<(), Text> {
    if (config.supplyUnit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (config.totalSupply % config.supplyUnit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    validateStructure(config.backingPairs);
  };
};
