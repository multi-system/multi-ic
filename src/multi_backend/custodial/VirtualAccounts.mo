import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Types "../types/Types";
import AccountTypes "../types/AccountTypes";
import TransferTypes "../types/TransferTypes";
import AmountOperations "../financial/AmountOperations";
import Result "mo:base/Result";
import Error "../error/Error";

module {
  public class VirtualAccounts(initialState : AccountTypes.AccountMap) {
    private let accounts = initialState;

    // Public testable validations that return bools
    public func hasInsufficientBalance(account : Types.Account, amount : Types.Amount) : Bool {
      let balanceAmount = getBalance(account, amount.token);
      balanceAmount.value < amount.value;
    };

    public func isValidAmount(amount : Types.Amount) : Bool {
      amount.value > 0;
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

    private func validateAmount(amount : Types.Amount, operation : Text) {
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

    private func updateBalance(account : Types.Account, amount : Types.Amount) {
      let balances = getOrCreateAccount(account);
      StableHashMap.put(balances, Principal.equal, Principal.hash, amount.token, amount.value);
    };

    private func getBalanceValue(account : Types.Account, token : Types.Token) : Nat {
      switch (StableHashMap.get(accounts, Principal.equal, Principal.hash, account)) {
        case (?balances) {
          Option.get(StableHashMap.get(balances, Principal.equal, Principal.hash, token), 0);
        };
        case null { 0 };
      };
    };

    public func getBalance(account : Types.Account, token : Types.Token) : Types.Amount {
      let value = getBalanceValue(account, token);
      { token; value };
    };

    public func mint(to : Types.Account, amount : Types.Amount) {
      validatePrincipals([to, amount.token]);
      validateAmount(amount, "Mint");

      let currentBalance = getBalance(to, amount.token);
      let updatedAmount = AmountOperations.add(currentBalance, amount);
      updateBalance(to, updatedAmount);
    };

    public func burn(from : Types.Account, amount : Types.Amount) {
      validatePrincipals([from, amount.token]);
      validateAmount(amount, "Burn");

      if (hasInsufficientBalance(from, amount)) {
        Debug.trap("Insufficient balance for burn");
      };

      let currentBalance = getBalance(from, amount.token);
      let result = AmountOperations.subtract(currentBalance, amount);

      switch (result) {
        case (#ok(updatedAmount)) {
          updateBalance(from, updatedAmount);
        };
        case (#err(error)) {
          Debug.trap("Error during burn: " # debug_show (error));
        };
      };
    };

    public func transfer(args : TransferTypes.TransferArgs) {
      validatePrincipals([args.from, args.to, args.amount.token]);
      validateAmount(args.amount, "Transfer");

      if (isSelfTransfer(args.from, args.to)) {
        Debug.trap("Self-transfers are not allowed");
      };

      if (hasInsufficientBalance(args.from, args.amount)) {
        Debug.trap("Insufficient balance");
      };

      let toBalance = getBalance(args.to, args.amount.token);
      let fromBalance = getBalance(args.from, args.amount.token);

      let subtractResult = AmountOperations.subtract(fromBalance, args.amount);

      switch (subtractResult) {
        case (#ok(updatedFromAmount)) {
          let updatedToAmount = AmountOperations.add(toBalance, args.amount);

          updateBalance(args.from, updatedFromAmount);
          updateBalance(args.to, updatedToAmount);
        };
        case (#err(error)) {
          Debug.trap("Error during transfer: " # debug_show (error));
        };
      };
    };

    public func getAllBalances(account : Types.Account) : [Types.Amount] {
      switch (StableHashMap.get(accounts, Principal.equal, Principal.hash, account)) {
        case (?balances) {
          let buffer = Buffer.Buffer<Types.Amount>(0);
          for ((token, balance) in StableHashMap.entries(balances)) {
            if (balance > 0) {
              buffer.add({ token; value = balance });
            };
          };
          Buffer.toArray(buffer);
        };
        case null { [] };
      };
    };
  };
};
