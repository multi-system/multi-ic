import Principal "mo:base/Principal";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Debug "mo:base/Debug";
import Result "mo:base/Result";

import Types "../../types/Types";
import VirtualAccounts "../../custodial/VirtualAccounts";
import VirtualAccountBridge "../../custodial/VirtualAccountBridge";
import StakeValidation "./StakeValidation";
import Error "../../error/Error";

module {
  public class StakeVault(
    userAccounts : VirtualAccounts.VirtualAccounts,
    multiToken : Types.Token,
    governanceToken : Types.Token,
  ) {
    private let stakeAccounts = VirtualAccounts.VirtualAccounts(
      StableHashMap.init<Types.Account, StableHashMap.StableHashMap<Types.Token, Nat>>()
    );

    public func getUserAccounts() : VirtualAccounts.VirtualAccounts {
      userAccounts;
    };

    // Basic staking function - moves tokens from user account to stake account
    public func stake(
      account : Types.Account,
      amount : Types.Amount,
    ) {
      VirtualAccountBridge.transfer(
        userAccounts,
        stakeAccounts,
        account,
        amount,
      );
    };

    /**
     * Returns excess tokens from the stake account back to the user account.
     * This is used when the final quantity is adjusted due to stake rate changes.
     *
     * @param account The account to return tokens to
     * @param amount The amount of tokens to return
     */
    public func returnExcessTokens(
      account : Types.Account,
      amount : Types.Amount,
    ) {
      VirtualAccountBridge.transfer(
        stakeAccounts,
        userAccounts,
        account,
        amount,
      );
    };

    /**
     * Validates balances and performs the staking operations required for a submission.
     * This validates that the user has sufficient balances for all tokens and then
     * transfers the tokens from the user account to the stake account.
     *
     * @param account The account performing the staking
     * @param tokenAmount The token amount to stake
     * @param govStake The governance token stake
     * @param multiStake The multi token stake
     * @returns Result with success or error
     */
    public func executeStakeTransfers(
      account : Types.Account,
      tokenAmount : Types.Amount,
      govStake : Types.Amount,
      multiStake : Types.Amount,
    ) : Result.Result<(), Error.CompetitionError> {
      // Validate balances
      switch (
        StakeValidation.validateSubmissionBalances(
          account,
          tokenAmount,
          govStake,
          multiStake,
          userAccounts,
        )
      ) {
        case (#err(error)) return #err(error);
        case (#ok()) {};
      };

      // Perform the staking operations
      stake(account, govStake);
      stake(account, multiStake);
      stake(account, tokenAmount);

      #ok(());
    };

    public func getTotalGovernanceStake() : Nat {
      stakeAccounts.getTotalBalance(governanceToken).value;
    };

    public func getTotalMultiStake() : Nat {
      stakeAccounts.getTotalBalance(multiToken).value;
    };

    public func getStakeAccounts() : VirtualAccounts.VirtualAccounts {
      stakeAccounts;
    };
  };
};
