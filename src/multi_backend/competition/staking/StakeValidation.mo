import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import Error "../../error/Error";
import BackingValidation "../../backing/BackingValidation";
import VirtualAccounts "../../custodial/VirtualAccounts";

// StakeValidation provides validation functions for stake operations
module {
  // Validates that a user has sufficient balance for a stake
  public func validateStakeBalance(
    account : Types.Account,
    stake : Types.Amount,
    virtualAccounts : VirtualAccounts.VirtualAccounts,
  ) : Result.Result<(), Error.CompetitionError> {
    switch (
      BackingValidation.checkSufficientBalance<Error.CompetitionError>(
        account,
        stake,
        virtualAccounts,
        func(e) {
          #InsufficientStake({
            token = e.token;
            required = e.required;
            available = e.balance;
          });
        },
      )
    ) {
      case (#err(e)) return #err(e);
      case (#ok(_)) #ok(());
    };
  };

  // Validates that the token is the expected type
  public func validateTokenType(
    stake : Types.Amount,
    expectedToken : Types.Token,
  ) : Result.Result<(), Error.CompetitionError> {
    if (not Principal.equal(stake.token, expectedToken)) {
      return #err(#InvalidSubmission({ reason = "Stake must be in expected token type: " # Principal.toText(expectedToken) # ", received: " # Principal.toText(stake.token) }));
    };
    #ok(());
  };

  // Validates that a token has an approved competition price
  public func validateTokenApproved(
    token : Types.Token,
    getCompetitionPrice : (Types.Token) -> ?Types.Price,
  ) : Result.Result<Types.Price, Error.CompetitionError> {
    switch (getCompetitionPrice(token)) {
      case (null) {
        #err(#TokenNotApproved(token));
      };
      case (?price) {
        #ok(price);
      };
    };
  };

  // Validates all balances required for a submission
  public func validateSubmissionBalances(
    account : Types.Account,
    proposedQuantity : Types.Amount,
    govStake : Types.Amount,
    multiStake : Types.Amount,
    virtualAccounts : VirtualAccounts.VirtualAccounts,
  ) : Result.Result<(), Error.CompetitionError> {
    // Check governance stake balance
    switch (validateStakeBalance(account, govStake, virtualAccounts)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    // Check multi stake balance
    switch (validateStakeBalance(account, multiStake, virtualAccounts)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    // Check proposed token balance
    switch (validateStakeBalance(account, proposedQuantity, virtualAccounts)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    #ok(());
  };
};
