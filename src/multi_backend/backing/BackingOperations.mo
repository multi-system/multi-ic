import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Types "../types/BackingTypes";
import VirtualAccounts "../ledger/VirtualAccounts";
import BackingMath "./BackingMath";

module {
  public type IssueResult = {
    totalSupply : Nat;
    amount : Nat;
  };

  public type RedeemResult = {
    totalSupply : Nat;
    amount : Nat;
  };

  public class BackingOperationsImpl(virtualAccounts : VirtualAccounts.VirtualAccountManager) {

    public func processIssue(
      caller : Principal,
      systemAccount : Principal,
      amount : Nat,
      supplyUnit : Nat,
      totalSupply : Nat,
      backingTokens : [Types.BackingPair],
    ) : Result.Result<IssueResult, Text> {
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

      for ((tokenId, requiredAmount) in requiredTransfers.vals()) {
        virtualAccounts.transfer({
          from = caller;
          to = systemAccount;
          token = tokenId;
          amount = requiredAmount;
        });
      };

      #ok({
        totalSupply = totalSupply + amount;
        amount = amount;
      });
    };

    public func processRedeem(
      caller : Principal,
      systemAccount : Principal,
      amount : Nat,
      supplyUnit : Nat,
      totalSupply : Nat,
      backingTokens : [Types.BackingPair],
    ) : Result.Result<RedeemResult, Text> {
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

      for ((tokenId, requiredAmount) in requiredTransfers.vals()) {
        virtualAccounts.transfer({
          from = systemAccount;
          to = caller;
          token = tokenId;
          amount = requiredAmount;
        });
      };

      #ok({
        totalSupply = totalSupply - amount;
        amount = amount;
      });
    };

    public func processBackingIncrease(
      amount : Nat,
      supplyUnit : Nat,
      totalSupply : Nat,
      backingTokens : [var Types.BackingPair],
    ) : Result.Result<IssueResult, Text> {
      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      switch (BackingMath.calculateEta(totalSupply + amount, supplyUnit)) {
        case (#err(e)) return #err(e);
        case (#ok(newEta)) {
          // Update all backing units
          for (i in backingTokens.keys()) {
            let pair = backingTokens[i];
            switch (BackingMath.calculateBackingUnits(pair.reserveQuantity, newEta)) {
              case (#err(e)) return #err(e);
              case (#ok(newBackingUnits)) {
                backingTokens[i] := {
                  tokenInfo = pair.tokenInfo;
                  backingUnit = newBackingUnits;
                  reserveQuantity = pair.reserveQuantity;
                };
              };
            };
          };

          #ok({
            totalSupply = totalSupply + amount;
            amount = amount;
          });
        };
      };
    };

    public func processBackingDecrease(
      amount : Nat,
      supplyUnit : Nat,
      totalSupply : Nat,
      backingTokens : [var Types.BackingPair],
    ) : Result.Result<RedeemResult, Text> {
      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      let newTotalSupply = totalSupply - amount;
      if (newTotalSupply < supplyUnit) {
        return #err("Total supply cannot be less than supply unit");
      };

      switch (BackingMath.calculateEta(newTotalSupply, supplyUnit)) {
        case (#err(e)) return #err(e);
        case (#ok(newEta)) {
          // Update all backing units
          for (i in backingTokens.keys()) {
            let pair = backingTokens[i];
            switch (BackingMath.calculateBackingUnits(pair.reserveQuantity, newEta)) {
              case (#err(e)) return #err(e);
              case (#ok(newBackingUnits)) {
                backingTokens[i] := {
                  tokenInfo = pair.tokenInfo;
                  backingUnit = newBackingUnits;
                  reserveQuantity = pair.reserveQuantity;
                };
              };
            };
          };

          #ok({
            totalSupply = newTotalSupply;
            amount = amount;
          });
        };
      };
    };
  };
};
