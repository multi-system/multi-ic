import Result "mo:base/Result";
import Types "../types/Types";
import Error "../error/Error";
import VirtualAccounts "../custodial/VirtualAccounts";
import AmountOperations "../financial/AmountOperations";

module {
  // Check if user has sufficient balance for a stake operation
  public func validateSubmissionBalances(
    account : Types.Account,
    proposedQuantity : Types.Amount,
    govStake : Types.Amount,
    multiStake : Types.Amount,
    userAccounts : VirtualAccounts.VirtualAccounts,
  ) : Result.Result<(), Error.CompetitionError> {
    // Helper to check a single balance
    func checkBalance(amount : Types.Amount) : Result.Result<(), Error.CompetitionError> {
      let balance = userAccounts.getBalance(account, amount.token);

      if (balance.value < amount.value) {
        return #err(#InsufficientStake({ token = amount.token; required = amount.value; available = balance.value }));
      };

      #ok(());
    };

    // Check each balance sequentially
    switch (checkBalance(govStake)) {
      case (#err(error)) return #err(error);
      case (#ok()) {};
    };

    switch (checkBalance(multiStake)) {
      case (#err(error)) return #err(error);
      case (#ok()) {};
    };

    switch (checkBalance(proposedQuantity)) {
      case (#err(error)) return #err(error);
      case (#ok()) {};
    };

    #ok(());
  };
};
