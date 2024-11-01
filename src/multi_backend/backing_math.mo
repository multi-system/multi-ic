import Result "mo:base/Result";
import Types "./backing_types";
import Int "mo:base/Int";

module {
  public func calculateEta(totalSupply : Nat, supplyUnit : Nat) : Result.Result<Nat, Text> {
    if (supplyUnit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (totalSupply % supplyUnit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    #ok(totalSupply / supplyUnit);
  };

  public func calculateBackingUnits(reserve : Nat, eta : Nat) : Nat {
    return reserve / eta;
  };

  public func validateBackingRatios(config : Types.BackingConfig) : Result.Result<(), Text> {
    switch (calculateEta(config.total_supply, config.supply_unit)) {
      case (#err(e)) return #err(e);
      case (#ok(eta)) {
        // Check if each backing pair's units match the required ratio
        for (pair in config.backing_pairs.vals()) {
          let required_units = calculateBackingUnits(pair.reserve, eta);
          if (required_units != pair.units) {
            return #err("Invalid backing ratio");
          };
        };
      };
    };
    #ok(());
  };
};
