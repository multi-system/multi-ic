import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Option "mo:base/Option";
import ICRC2 "mo:icrc2-types";
import Error "mo:base/Error";
import VirtualAccounts "./VirtualAccounts";
import TokenRegistry "../token/TokenRegistry";
import ErrorModule "../error/Error";

module {
  public class CustodialManager(
    tokenRegistry : TokenRegistry.TokenRegistryManager,
    virtualAccounts : VirtualAccounts.VirtualAccounts,
    owner : Principal,
  ) {
    private let ledgers = HashMap.HashMap<Principal, ICRC2.Service>(10, Principal.equal, Principal.hash);

    public func setupLedger<system>(tokenId : Principal) {
      let ledger = actor (Principal.toText(tokenId)) : ICRC2.Service;
      ledgers.put(tokenId, ledger);
    };

    public func initializeLedgers<system>(tokenIds : [Principal]) {
      for (tokenId in tokenIds.vals()) {
        if (Option.isNull(ledgers.get(tokenId))) {
          setupLedger<system>(tokenId);
        };
      };
    };

    public func addLedger(tokenId : Principal) : async* Result.Result<(), ErrorModule.ApprovalError> {
      setupLedger<system>(tokenId);
      return #ok();
    };

    public func getLedger(tokenId : Principal) : Result.Result<ICRC2.Service, ErrorModule.OperationError> {
      if (not tokenRegistry.isApproved(tokenId)) {
        return #err(#TokenNotApproved(tokenId));
      };

      let ?ledger = ledgers.get(tokenId) else {
        let newLedger = actor (Principal.toText(tokenId)) : ICRC2.Service;
        ledgers.put(tokenId, newLedger);
        return #ok(newLedger);
      };

      return #ok(ledger);
    };

    public func withdraw(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), ErrorModule.TransferError> {
      let ledgerResult = getLedger(token);

      switch (ledgerResult) {
        case (#err(#TokenNotApproved(token))) {
          return #err(#TokenNotSupported(token));
        };
        case (#err(_)) {
          return #err(#TransferFailed({ token; error = "Unexpected error retrieving ledger" }));
        };
        case (#ok(ledger)) {
          let fee = await ledger.icrc1_fee();
          if (amount <= fee) {
            return #err(#TransferFailed({ token; error = "Amount must be greater than fee" }));
          };

          let balance = virtualAccounts.getBalance(caller, token);
          if (balance < amount) {
            return #err(#InsufficientBalance({ token = token; required = amount; balance = balance }));
          };

          virtualAccounts.burn(caller, token, amount);
          try {
            switch (await ledger.icrc1_transfer({ from_subaccount = null; to = { owner = caller; subaccount = null }; amount = amount - fee; fee = ?fee; memo = null; created_at_time = null })) {
              case (#Ok(_)) {
                return #ok(());
              };
              case (#Err(e)) {
                virtualAccounts.mint(caller, token, amount);
                return #err(#TransferFailed({ token; error = debug_show (e) }));
              };
            };
          } catch (e) {
            virtualAccounts.mint(caller, token, amount);
            return #err(#TransferFailed({ token; error = Error.message(e) }));
          };
        };
      };
    };

    public func deposit(caller : Principal, token : Principal, amount : Nat) : async* Result.Result<(), ErrorModule.TransferError> {
      let ledgerResult = getLedger(token);

      switch (ledgerResult) {
        case (#err(#TokenNotApproved(token))) {
          return #err(#TokenNotSupported(token));
        };
        case (#err(_)) {
          return #err(#TransferFailed({ token; error = "Unexpected error retrieving ledger" }));
        };
        case (#ok(ledger)) {
          let fee = await ledger.icrc1_fee();
          if (amount <= fee) {
            return #err(#TransferFailed({ token; error = "Amount must be greater than fee" }));
          };

          switch (await ledger.icrc2_transfer_from({ from = { owner = caller; subaccount = null }; to = { owner = owner; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null; spender_subaccount = null })) {
            case (#Ok(_)) {
              virtualAccounts.mint(caller, token, amount - fee);
              return #ok(());
            };
            case (#Err(e)) {
              return #err(#TransferFailed({ token; error = debug_show (e) }));
            };
          };
        };
      };
    };

    public func getLedgerFee(tokenId : Principal) : async* Result.Result<Nat, ErrorModule.OperationError> {
      let ledgerResult = getLedger(tokenId);

      switch (ledgerResult) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok(ledger)) {
          try {
            return #ok(await ledger.icrc1_fee());
          } catch (e) {
            return #err(#InvalidAmount({ reason = "Failed to get fee: " # Error.message(e); amount = 0 }));
          };
        };
      };
    };
  };
};
