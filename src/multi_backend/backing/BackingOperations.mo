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
    public func processIssue(
      caller : Principal,
      amount : Nat,
    ) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let totalSupply = store.getTotalSupply();
      let backingTokens = store.getBackingTokens();

      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      let requiredTransfers = Buffer.Buffer<(Principal, Nat)>(backingTokens.size());

      for (pair in backingTokens.vals()) {
        switch (BackingMath.calculateRequiredBacking(amount, supplyUnit, pair)) {
          case (#err(e)) { return #err(e) };
          case (#ok(requiredAmount)) {
            let balance = virtualAccounts.getBalance(caller, pair.tokenInfo.canisterId);
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
          from = caller;
          to = systemAccount;
          token = tokenId;
          amount = requiredAmount;
        });
      };

      // Update total supply
      switch (store.updateTotalSupply(totalSupply + amount)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      #ok(());
    };

    public func processRedeem(
      caller : Principal,
      amount : Nat,
    ) : Result.Result<(), Text> {
      let supplyUnit = store.getSupplyUnit();
      let totalSupply = store.getTotalSupply();
      let backingTokens = store.getBackingTokens();

      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      switch (BackingMath.calculateEta(totalSupply, supplyUnit)) {
        case (#err(e)) return #err(e);
        case (#ok(eta)) {
          let requestedUnits = amount / supplyUnit;
          if (requestedUnits > eta) {
            return #err("Cannot redeem more units than eta (M/u)");
          };
        };
      };

      let requiredTransfers = Buffer.Buffer<(Principal, Nat)>(backingTokens.size());

      for (pair in backingTokens.vals()) {
        switch (BackingMath.calculateRequiredBacking(amount, supplyUnit, pair)) {
          case (#err(e)) { return #err(e) };
          case (#ok(requiredAmount)) {
            let balance = virtualAccounts.getBalance(systemAccount, pair.tokenInfo.canisterId);
            if (balance < requiredAmount) {
              return #err("Insufficient system balance for token " # Principal.toText(pair.tokenInfo.canisterId));
            };
            requiredTransfers.add((pair.tokenInfo.canisterId, requiredAmount));
          };
        };
      };

      // Execute transfers
      for ((tokenId, requiredAmount) in requiredTransfers.vals()) {
        virtualAccounts.transfer({
          from = systemAccount;
          to = caller;
          token = tokenId;
          amount = requiredAmount;
        });
      };

      // Update total supply
      switch (store.updateTotalSupply(totalSupply - amount)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      #ok(());
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
  };
};
