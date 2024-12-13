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

module {
  public class LedgerManager(
    owner : Principal,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) {
    private let ledgers = HashMap.HashMap<Principal, ICRC2.Service>(10, Principal.equal, Principal.hash);

    public func setupLedger<system>(tokenId : Principal) {
      let ledger = actor (Principal.toText(tokenId)) : ICRC2.Service;
      ledgers.put(tokenId, ledger);
    };

    public func initializeLedgers<system>(tokenIds : [Principal]) {
      for (tokenId in tokenIds.vals()) {
        if (Option.isNull(ledgers.get(tokenId))) {
          setupLedger(tokenId);
        };
      };
    };

    public func withdraw(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), Text> {
      let ?ledger = ledgers.get(token) else return #err("Ledger not found");
      let fee = await ledger.icrc1_fee();

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
          case (#Ok(_)) { #ok(()) };
          case (#Err(e)) {
            virtualAccounts.mint(caller, token, amount);
            #err("Transfer failed: " # debug_show (e));
          };
        };
      } catch (e) {
        virtualAccounts.mint(caller, token, amount);
        #err("System error: " # Error.message(e));
      };
    };

    public func deposit(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), Text> {
      let ?ledger = ledgers.get(token) else return #err("Ledger not found");
      let fee = await ledger.icrc1_fee();

      if (amount <= fee) {
        return #err("Amount must be greater than fee");
      };

      switch (await ledger.icrc2_transfer_from({ from = { owner = caller; subaccount = null }; to = { owner = owner; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null; spender_subaccount = null })) {
        case (#Ok(_)) {
          virtualAccounts.mint(caller, token, amount - fee);
          #ok(());
        };
        case (#Err(e)) {
          #err("Transfer failed: " # debug_show (e));
        };
      };
    };

    public func getLedgerFee(tokenId : Principal) : async* Result.Result<Nat, Text> {
      switch (ledgers.get(tokenId)) {
        case (null) { #err("Ledger not found") };
        case (?ledger) {
          try {
            #ok(await ledger.icrc1_fee());
          } catch (e) {
            #err("Failed to get fee: " # Error.message(e));
          };
        };
      };
    };

    public func getLedger(tokenId : Principal) : ?ICRC2.Service {
      ledgers.get(tokenId);
    };
  };
};
