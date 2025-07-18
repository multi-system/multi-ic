import Principal "mo:base/Principal";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Debug "mo:base/Debug";
import Result "mo:base/Result";

import Types "../../types/Types";
import VirtualAccounts "../../custodial/VirtualAccounts";
import VirtualAccountBridge "../../custodial/VirtualAccountBridge";
import StakeValidation "./StakeValidation";
import Error "../../error/Error";
import AccountTypes "../../types/AccountTypes";

module {
  public class StakeVault(
    userAccounts : VirtualAccounts.VirtualAccounts,
    multiToken : Types.Token,
    governanceToken : Types.Token,
    existingStakeAccounts : AccountTypes.AccountMap,
  ) {
    private let stakeAccounts = VirtualAccounts.VirtualAccounts(existingStakeAccounts);

    // Define the pool account for reward distribution
    private let poolAccount : Types.Account = Principal.fromText("be2us-64aaa-aaaaa-qaabq-cai");

    public func getUserAccounts() : VirtualAccounts.VirtualAccounts {
      userAccounts;
    };

    // Get the stake accounts map for persistence
    public func getStakeAccountsMap() : AccountTypes.AccountMap {
      existingStakeAccounts;
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

    // Unstaking function - moves tokens from stake account back to user account
    // Note: This is only used as a consequence of reward distribution
    public func unstake(
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
     * Transfer tokens to the pool account within stake accounts.
     * Used to collect all stakes before distribution.
     *
     * @param fromAccount The account to transfer from
     * @param amount The amount to transfer to pool
     */
    public func transferToPool(
      fromAccount : Types.Account,
      amount : Types.Amount,
    ) {
      stakeAccounts.transfer({
        from = fromAccount;
        to = poolAccount;
        amount = amount;
      });
    };

    /**
     * Transfer from pool account back to a user account.
     * Used during reward distribution.
     *
     * @param toAccount The account to transfer to
     * @param amount The amount to transfer from pool
     */
    public func transferFromPoolToUser(
      toAccount : Types.Account,
      amount : Types.Amount,
    ) {
      // Step 1: Transfer from pool to user's account within stakeAccounts
      stakeAccounts.transfer({
        from = poolAccount;
        to = toAccount;
        amount = amount;
      });

      // Step 2: Use unstake to move from stakeAccounts to userAccounts
      unstake(toAccount, amount);
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
      unstake(account, amount);
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

    public func getPoolAccount() : Types.Account {
      poolAccount;
    };

    /**
     * Get the current balance of the pool for a specific token
     */
    public func getPoolBalance(token : Types.Token) : Types.Amount {
      stakeAccounts.getBalance(poolAccount, token);
    };
  };
};
