import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Types "../types/BackingTypes";
import VirtualAccounts "../ledger/VirtualAccounts";
import BackingMath "./BackingMath";
import BackingStore "./BackingStore";

module {
  public class BackingOperationsImpl(
    store : BackingStore.BackingStore,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    systemAccount : Principal,
  ) {
    // Helper function that reconfigures reserve ratios based on new supply
    private func reconfigureReserve(
      newTotalSupply : Nat,
      supplyUnit : Nat,
      backingTokens : [Types.BackingPair],
    ) : Result.Result<(), Text> {
      switch (BackingMath.calculateBacking(newTotalSupply, supplyUnit, backingTokens, virtualAccounts, systemAccount)) {
        case (#err(e)) return #err(e);
        case (#ok(backingUnits)) {
          let newPairs = Array.mapEntries<Types.BackingPair, Types.BackingPair>(
            backingTokens,
            func(pair : Types.BackingPair, index : Nat) : Types.BackingPair {
              {
                tokenInfo = pair.tokenInfo;
                backingUnit = backingUnits[index];
              };
            },
          );

          switch (store.updateBackingTokens(newPairs)) {
            case (#err(e)) return #err(e);
            case (#ok()) {};
          };

          switch (store.updateTotalSupply(newTotalSupply)) {
            case (#err(e)) return #err(e);
            case (#ok()) {};
          };

          #ok(());
        };
      };
    };

    // Helper function that scales reserve up/down while maintaining ratios
    private func scaleReserve(
      amount : Nat,
      from : Principal,
      to : Principal,
      checkBalanceFor : Principal,
      supplyUnit : Nat,
      backingTokens : [Types.BackingPair],
      updateSupplyAmount : Int,
    ) : Result.Result<(), Text> {
      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      let requiredTransfers = Buffer.Buffer<(Principal, Nat)>(backingTokens.size());

      for (pair in backingTokens.vals()) {
        switch (BackingMath.calculateRequiredBacking(amount, supplyUnit, pair)) {
          case (#err(e)) { return #err(e) };
          case (#ok(requiredAmount)) {
            let balance = virtualAccounts.getBalance(checkBalanceFor, pair.tokenInfo.canisterId);
            if (balance < requiredAmount) {
              return #err("Insufficient balance for token " # Principal.toText(pair.tokenInfo.canisterId));
            };
            requiredTransfers.add((pair.tokenInfo.canisterId, requiredAmount));
          };
        };
      };

      // Execute transfers
      for ((tokenId, requiredAmount) in requiredTransfers.vals()) {
        virtualAccounts.transfer({
          from = from;
          to = to;
          token = tokenId;
          amount = requiredAmount;
        });
      };

      // Update total supply
      let totalSupply = store.getTotalSupply();
      let newSupply = if (updateSupplyAmount >= 0) {
        totalSupply + amount;
      } else {
        totalSupply - amount;
      };

      switch (store.updateTotalSupply(newSupply)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      #ok(());
    };

    public func processIssue(
      caller : Principal,
      amount : Nat,
    ) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let backingTokens = store.getBackingTokens();

      scaleReserve(
        amount,
        caller,
        systemAccount,
        caller,
        supplyUnit,
        backingTokens,
        +amount,
      );
    };

    public func processRedeem(
      caller : Principal,
      amount : Nat,
    ) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let totalSupply = store.getTotalSupply();
      let backingTokens = store.getBackingTokens();

      // Additional validation specific to redeem
      switch (BackingMath.calculateEta(totalSupply, supplyUnit)) {
        case (#err(e)) return #err(e);
        case (#ok(eta)) {
          let requestedUnits = amount / supplyUnit;
          if (requestedUnits > eta) {
            return #err("Cannot redeem more units than eta (M/u)");
          };
        };
      };

      scaleReserve(
        amount,
        systemAccount,
        caller,
        systemAccount,
        supplyUnit,
        backingTokens,
        -amount,
      );
    };

    public func processSupplyIncrease(amount : Nat) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let totalSupply = store.getTotalSupply();
      let backingTokens = store.getBackingTokens();

      switch (store.validateBackingUpdate(amount)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      let newTotalSupply = totalSupply + amount;
      reconfigureReserve(newTotalSupply, supplyUnit, backingTokens);
    };

    public func processSupplyDecrease(amount : Nat) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let totalSupply = store.getTotalSupply();
      let backingTokens = store.getBackingTokens();

      switch (store.validateBackingUpdate(amount)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      let newTotalSupply = totalSupply - amount;
      if (newTotalSupply < supplyUnit) {
        return #err("Total supply cannot be less than supply unit");
      };

      reconfigureReserve(newTotalSupply, supplyUnit, backingTokens);
    };
  };
};
