import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Types "../types/Types";
import AccountTypes "../types/AccountTypes";
import TransferTypes "../types/TransferTypes";

module {
  public class VirtualAccountManager(initialState : AccountTypes.AccountMap) {
    private let accounts = initialState;

    // Public testable validations that return bools
    public func hasInsufficientBalance(account : Types.Account, token : Types.Token, amount : Nat) : Bool {
      getBalance(account, token) < amount;
    };

    public func isValidAmount(amount : Nat) : Bool {
      amount > 0;
    };

    public func isSelfTransfer(from : Types.Account, to : Types.Account) : Bool {
      Principal.equal(from, to);
    };

    public func hasValidPrincipals(principals : [Principal]) : Bool {
      for (p in principals.vals()) {
        if (Principal.isAnonymous(p)) {
          return false;
        };
      };
      true;
    };

    private func validatePrincipals(principals : [Principal]) {
      if (not hasValidPrincipals(principals)) {
        Debug.trap("Invalid principal detected");
      };
    };

    private func validateAmount(amount : Nat, operation : Text) {
      if (not isValidAmount(amount)) {
        Debug.trap(operation # " amount cannot be zero");
      };
    };

    private func getOrCreateAccount(account : Types.Account) : AccountTypes.BalanceMap {
      switch (StableHashMap.get(accounts, Principal.equal, Principal.hash, account)) {
        case (?balances) { balances };
        case null {
          let balances = StableHashMap.init<Principal, Nat>();
          StableHashMap.put(accounts, Principal.equal, Principal.hash, account, balances);
          balances;
        };
      };
    };

    private func updateBalance(account : Types.Account, token : Types.Token, amount : Nat) {
      let balances = getOrCreateAccount(account);
      StableHashMap.put(balances, Principal.equal, Principal.hash, token, amount);
    };

    public func getBalance(account : Types.Account, token : Types.Token) : Nat {
      switch (StableHashMap.get(accounts, Principal.equal, Principal.hash, account)) {
        case (?balances) {
          Option.get(StableHashMap.get(balances, Principal.equal, Principal.hash, token), 0);
        };
        case null { 0 };
      };
    };

    public func mint(to : Types.Account, token : Types.Token, amount : Nat) {
      validatePrincipals([to, token]);
      validateAmount(amount, "Mint");

      let currentBalance = getBalance(to, token);
      updateBalance(to, token, currentBalance + amount);
    };

    public func burn(from : Types.Account, token : Types.Token, amount : Nat) {
      validatePrincipals([from, token]);
      validateAmount(amount, "Burn");

      if (hasInsufficientBalance(from, token, amount)) {
        Debug.trap("Insufficient balance for burn");
      };

      let currentBalance = getBalance(from, token);
      updateBalance(from, token, currentBalance - amount);
    };

    public func transfer(args : TransferTypes.TransferArgs) {
      validatePrincipals([args.from, args.to, args.token]);
      validateAmount(args.amount, "Transfer");

      if (isSelfTransfer(args.from, args.to)) {
        Debug.trap("Self-transfers are not allowed");
      };

      if (hasInsufficientBalance(args.from, args.token, args.amount)) {
        Debug.trap("Insufficient balance");
      };

      let toBalance = getBalance(args.to, args.token);
      let fromBalance = getBalance(args.from, args.token);

      updateBalance(args.from, args.token, fromBalance - args.amount);
      updateBalance(args.to, args.token, toBalance + args.amount);
    };

    public func getAllBalances(account : Types.Account) : [(Types.Token, Nat)] {
      switch (StableHashMap.get(accounts, Principal.equal, Principal.hash, account)) {
        case (?balances) {
          let buffer = Buffer.Buffer<(Types.Token, Nat)>(0);
          for ((token, balance) in StableHashMap.entries(balances)) {
            if (balance > 0) {
              buffer.add((token, balance));
            };
          };
          Buffer.toArray(buffer);
        };
        case null { [] };
      };
    };
  };
};
