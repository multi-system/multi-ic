import Result "mo:base/Result";
import Types "../types/BackingTypes";
import Int "mo:base/Int";

module {
  /// Calculates eta value from total supply and supply unit
  public func calculateEta(totalSupply : Nat, supplyUnit : Nat) : Result.Result<Nat, Text> {
    if (supplyUnit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (totalSupply % supplyUnit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    #ok(totalSupply / supplyUnit);
  };

  /// Calculates backing units from reserve quantity and eta
  public func calculateBackingUnits(reserveQuantity : Nat, eta : Nat) : Result.Result<Nat, Text> {
    if (eta == 0) {
      return #err("Eta cannot be zero");
    };
    #ok(reserveQuantity / eta);
  };

  /// Validates backing ratios in configuration
  public func validateBackingRatios(config : Types.BackingConfig) : Result.Result<(), Text> {
    switch (calculateEta(config.totalSupply, config.supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok(eta)) {
        for (pair in config.backingPairs.vals()) {
          switch (calculateBackingUnits(pair.reserveQuantity, eta)) {
            case (#err(e)) return #err(e);
            case (#ok(requiredUnits)) {
              if (requiredUnits != pair.backingUnit) {
                return #err("Invalid backing ratio");
              };
            };
          };
        };
      };
    };
    #ok(());
  };

  /// Calculates required backing amount for a given transfer
  public func calculateRequiredBacking(amount : Nat, supplyUnit : Nat, pair : Types.BackingPair) : Result.Result<Nat, Text> {
    if (amount % supplyUnit != 0) {
      return #err("Amount must be multiple of supply unit");
    };

    let supplyUnits = amount / supplyUnit;
    #ok(supplyUnits * pair.backingUnit);
  };
};
