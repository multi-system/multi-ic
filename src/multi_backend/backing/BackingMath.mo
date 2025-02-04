import Result "mo:base/Result";
import Types "../types/BackingTypes";
import Int "mo:base/Int";
import Buffer "mo:base/Buffer";

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
  public func calculateBackingUnit(reserveQuantity : Nat, eta : Nat) : Result.Result<Nat, Text> {
    if (eta == 0) {
      return #err("Eta cannot be zero");
    };
    #ok(reserveQuantity / eta);
  };

  /// Calculates backing units for all pairs
  public func calculateBacking(
    totalSupply : Nat,
    supplyUnit : Nat,
    backingPairs : [Types.BackingPair],
  ) : Result.Result<[Nat], Text> {
    switch (calculateEta(totalSupply, supplyUnit)) {
      case (#err(e)) #err(e);
      case (#ok(eta)) {
        let units = Buffer.Buffer<Nat>(backingPairs.size());
        for (pair in backingPairs.vals()) {
          switch (calculateBackingUnit(pair.reserveQuantity, eta)) {
            case (#err(e)) return #err(e);
            case (#ok(unit)) units.add(unit);
          };
        };
        #ok(Buffer.toArray(units));
      };
    };
  };
  /// Validates backing ratios in configuration
  public func validateBackingRatios(config : Types.BackingConfig) : Result.Result<(), Text> {
    switch (calculateEta(config.totalSupply, config.supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok(eta)) {
        for (pair in config.backingPairs.vals()) {
          switch (calculateBackingUnit(pair.reserveQuantity, eta)) {
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
