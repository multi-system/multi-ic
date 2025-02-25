import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import ICRC2 "mo:icrc2-types";
import Error "mo:base/Error";
import VirtualAccounts "./VirtualAccounts";
import TokenRegistry "../tokens/TokenRegistry";

module {
  public class LedgerManager(
    tokenRegistry : TokenRegistry.TokenRegistryManager,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    owner : Principal,
  ) {
    private let ledgers = HashMap.HashMap<Principal, ICRC2.Service>(10, Principal.equal, Principal.hash);

    public func getLedger(tokenId : Principal) : Result.Result<ICRC2.Service, Text> {
      if (! tokenRegistry.isApproved(tokenId)) {
        return #err("Token not approved");
      };

      let ?existingLedger = ledgers.get(tokenId);

      switch (existingLedger) {
        case (?ledger) : return #ok(ledger);
        case null : let newLedger = actor (Principal.toText(tokenId)) : ICRC2.Service;
        ledgers.put(tokenId, newLedger);
        return #ok(newLedger);
      };
    };

    public func withdraw(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), Text> {
      let ledgerResult = getLedger(token);
      switch (ledgerResult) {
        case (#err(e)) : return #err(e);
        case (#ok(ledger)) : let fee = await ledger.icrc1_fee();
        if (amount <= fee) {
          return #err("Amount must be greater than fee");
        };
        let balance = virtualAccounts.getBalance(caller, token);
        if (balance < amount) {
          return #err("Insufficient virtual balance");
        };
        virtualAccounts.burn(caller, token, amount);
        try {
          switch (await ledger.icrc1_transfer({ from_subaccount = null; to = { owner = caller; subaccount = null }; amount = amount - fee; fee = ?fee; memo = null; created_at_time = null })) {
            case (#Ok(_)) : return #ok(());
            case (#Err(e)) : {
              virtualAccounts.mint(caller, token, amount);
              return #err("Transfer failed: " # debug_show (e));
            };
          };
        } catch (e) {
          virtualAccounts.mint(caller, token, amount);
          return #err("System error: " # Error.message(e));
        };
      };
    };

    public func deposit(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), Text> {
      let ledgerResult = getLedger(token);
      switch (ledgerResult) {
        case (#err(e)) : return #err(e);
        case (#ok(ledger)) : let fee = await ledger.icrc1_fee();
        if (amount <= fee) {
          return #err("Amount must be greater than fee");
        };
        switch (await ledger.icrc2_transfer_from({ from = { owner = caller; subaccount = null }; to = { owner = owner; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null; spender_subaccount = null })) {
          case (#Ok(_)) : {
            virtualAccounts.mint(caller, token, amount - fee);
            return #ok(());
          };
          case (#Err(e)) : {
            return #err("Transfer failed: " # debug_show (e));
          };
        };
      };
    };

    public func getLedgerFee(tokenId : Principal) : async* Result.Result<Nat, Text> {
      let ledgerResult = getLedger(tokenId);
      switch (ledgerResult) {
        case (#err(e)) : return #err(e);
        case (#ok(ledger)) : try {
          return #ok(await ledger.icrc1_fee());
        } catch (e) {
          return #err("Failed to get fee: " # Error.message(e));
        };
      };
    };
  };
};
