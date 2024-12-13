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

  public class BackingOperationsImpl(virtualAccounts : VirtualAccounts.VirtualAccountManager) {
    public func processIssue(
      caller : Principal,
      systemAccount : Principal,
      amount : Nat,
      supplyUnit : Nat,
      totalSupply : Nat,
      backingTokens : [Types.BackingPair],
    ) : Result.Result<IssueResult, Text> {

      // Validate supply unit alignment first
      if (amount % supplyUnit != 0) {
        return #err("Amount must be multiple of supply unit");
      };

      // Pre-validate all balances and calculate required amounts
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

      // All validation passed - now execute transfers atomically
      for ((tokenId, requiredAmount) in requiredTransfers.vals()) {
        // This will trap on any unexpected failure, rolling back all changes
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
  };
};
