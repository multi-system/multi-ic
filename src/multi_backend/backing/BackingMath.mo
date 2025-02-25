import Types "../types/BackingTypes";
import Buffer "mo:base/Buffer";
import VirtualAccounts "../ledger/VirtualAccounts";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

module {
  public func calculateEta(totalSupply : Nat, supplyUnit : Nat) : Nat {
    if (supplyUnit == 0) {
      Debug.trap("Supply unit cannot be zero in eta calculation");
    };
    if (totalSupply % supplyUnit != 0) {
      Debug.trap("Total supply must be divisible by supply unit in eta calculation");
    };
    totalSupply / supplyUnit;
  };

  public func calculateBackingUnit(reserveQuantity : Nat, eta : Nat) : Nat {
    if (eta == 0) {
      Debug.trap("Eta cannot be zero in backing unit calculation");
    };
    reserveQuantity / eta;
  };

  public func calculateBacking(
    totalSupply : Nat,
    supplyUnit : Nat,
    backingPairs : [Types.BackingPair],
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    systemAccount : Principal,
  ) : [Nat] {
    let eta = calculateEta(totalSupply, supplyUnit);
    let units = Buffer.Buffer<Nat>(backingPairs.size());

    for (pair in backingPairs.vals()) {
      let reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.tokenInfo.canisterId);
      let unit = calculateBackingUnit(reserveQuantity, eta);
      units.add(unit);
    };

    Buffer.toArray(units);
  };

  public func calculateRequiredBacking(amount : Nat, supplyUnit : Nat, pair : Types.BackingPair) : Nat {
    if (supplyUnit == 0) {
      Debug.trap("Supply unit cannot be zero in backing calculation");
    };
    if (amount % supplyUnit != 0) {
      Debug.trap("Amount must be divisible by supply unit in backing calculation");
    };

    let supplyUnits = amount / supplyUnit;
    supplyUnits * pair.backingUnit;
  };
};
