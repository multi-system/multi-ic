import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Types "./backing_types";

module {
  public func validateBacking(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.units == 0) {
        return #err("Backing units must be greater than 0");
      };

      if (pair.reserve == 0) {
        return #err("Reserve must be greater than 0");
      };

      let token_principal = Principal.fromActor(pair.token_info.token);
      var isDuplicate = false;
      for (existingPrincipal in seen.vals()) {
        if (existingPrincipal == token_principal) {
          isDuplicate := true;
        };
      };
      if (isDuplicate) {
        return #err("Duplicate token in backing");
      };
      seen.add(token_principal);
    };

    #ok(());
  };

  // Initial structure validation without checking reserves
  public func validateStructure(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.units == 0) {
        return #err("Backing units must be greater than 0");
      };

      let token_principal = Principal.fromActor(pair.token_info.token);
      var isDuplicate = false;
      for (existingPrincipal in seen.vals()) {
        if (existingPrincipal == token_principal) {
          isDuplicate := true;
        };
      };
      if (isDuplicate) {
        return #err("Duplicate token in backing");
      };
      seen.add(token_principal);
    };

    #ok(());
  };

  public func validateBackingConfig(config : Types.BackingConfig) : Result.Result<(), Text> {
    // Validate supply unit first
    if (config.supply_unit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (config.total_supply % config.supply_unit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    validateStructure(config.backing_pairs);
  };
};
