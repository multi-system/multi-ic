import Principal "mo:base/Principal";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Types "../types/VirtualTypes";

module {
  public class VirtualAccountManager() {
    private let accounts = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Nat>>(
      10,
      Principal.equal,
      Principal.hash,
    );

    private func getOrCreateAccount(account : Types.Account) : HashMap.HashMap<Principal, Nat> {
      switch (accounts.get(account)) {
        case (?balances) { balances };
        case null {
          let balances = HashMap.HashMap<Principal, Nat>(10, Principal.equal, Principal.hash);
          accounts.put(account, balances);
          balances;
        };
      };
    };

    public func getBalance(account : Types.Account, token : Principal) : Nat {
      switch (accounts.get(account)) {
        case (?balances) {
          switch (balances.get(token)) {
            case (?balance) { balance };
            case null { 0 };
          };
        };
        case null { 0 };
      };
    };

    public func mint(to : Types.Account, token : Principal, amount : Nat) {
      if (Principal.isAnonymous(to) or Principal.isAnonymous(token)) {
        Debug.trap("Invalid principal in mint");
      };

      if (amount == 0) {
        Debug.trap("Mint amount cannot be zero");
      };

      let toAccount = getOrCreateAccount(to);
      let currentBalance = Option.get(toAccount.get(token), 0);
      toAccount.put(token, currentBalance + amount);
    };

    public func burn(from : Types.Account, token : Principal, amount : Nat) {
      if (Principal.isAnonymous(from) or Principal.isAnonymous(token)) {
        Debug.trap("Invalid principal in burn");
      };

      if (amount == 0) {
        Debug.trap("Burn amount cannot be zero");
      };

      let fromBalance = getBalance(from, token);
      if (fromBalance < amount) {
        Debug.trap("Insufficient balance for burn");
      };

      let fromAccount = getOrCreateAccount(from);
      fromAccount.put(token, fromBalance - amount);
    };

    public func transfer(args : Types.TransferArgs) : () {
      if (Principal.isAnonymous(args.from) or Principal.isAnonymous(args.to) or Principal.isAnonymous(args.token)) {
        Debug.trap("Invalid principal in transfer");
      };

      if (args.amount == 0) {
        Debug.trap("Transfer amount cannot be zero");
      };

      let fromBalance = getBalance(args.from, args.token);
      if (fromBalance < args.amount) {
        Debug.trap("Insufficient balance");
      };

      let fromAccount = getOrCreateAccount(args.from);
      let toAccount = getOrCreateAccount(args.to);

      fromAccount.put(args.token, fromBalance - args.amount);
      let toBalance = Option.get(toAccount.get(args.token), 0);
      toAccount.put(args.token, toBalance + args.amount);
    };

    public func getAllBalances(account : Types.Account) : [(Principal, Nat)] {
      switch (accounts.get(account)) {
        case (?balances) {
          let buffer = Buffer.Buffer<(Principal, Nat)>(0);
          for ((token, balance) in balances.entries()) {
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
