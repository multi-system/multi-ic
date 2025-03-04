import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Buffer "mo:base/Buffer";
import VirtualAccounts "../custodial/VirtualAccounts";
import AmountOperations "../financial/AmountOperations";
import Debug "mo:base/Debug";

module {
  public func calculateEta(multiAmount : Types.Amount, supplyUnit : Nat) : Nat {
    if (supplyUnit == 0) {
      Debug.trap("Supply unit cannot be zero in eta calculation");
    };
    if (multiAmount.value % supplyUnit != 0) {
      Debug.trap("Amount must be divisible by supply unit in eta calculation");
    };
    multiAmount.value / supplyUnit;
  };

  public func calculateBackingUnit(reserveAmount : Types.Amount, eta : Nat) : Nat {
    if (eta == 0) {
      Debug.trap("Eta cannot be zero in backing unit calculation");
    };
    AmountOperations.divideByScalar(reserveAmount, eta).value;
  };

  public func calculateBacking(
    multiAmount : Types.Amount,
    supplyUnit : Nat,
    backingPairs : [BackingTypes.BackingPair],
    virtualAccounts : VirtualAccounts.VirtualAccounts,
    systemAccount : Types.Account,
  ) : [Nat] {
    let eta = calculateEta(multiAmount, supplyUnit);
    let units = Buffer.Buffer<Nat>(backingPairs.size());

    for (pair in backingPairs.vals()) {
      let reserveAmount = virtualAccounts.getBalance(systemAccount, pair.token);
      let unit = calculateBackingUnit(reserveAmount, eta);
      units.add(unit);
    };

    Buffer.toArray(units);
  };

  public func calculateRequiredBacking(multiAmount : Types.Amount, supplyUnit : Nat, pair : BackingTypes.BackingPair) : Types.Amount {
    if (supplyUnit == 0) {
      Debug.trap("Supply unit cannot be zero in backing calculation");
    };
    if (multiAmount.value % supplyUnit != 0) {
      Debug.trap("Amount must be divisible by supply unit in backing calculation");
    };

    let supplyUnits = multiAmount.value / supplyUnit;
    AmountOperations.new(pair.token, supplyUnits * pair.backingUnit);
  };
};
