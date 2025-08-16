import Principal "mo:base/Principal";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Array "mo:base/Array";

import Types "../../types/Types";
import VirtualAccounts "../../custodial/VirtualAccounts";
import VirtualAccountBridge "../../custodial/VirtualAccountBridge";
import StakeValidation "./StakeValidation";
import Error "../../error/Error";
import AccountTypes "../../types/AccountTypes";
import StakeTokenTypes "../../types/StakeTokenTypes";

module {
  public class StakeVault(
    userAccounts : VirtualAccounts.VirtualAccounts,
    stakeTokenConfigs : [StakeTokenTypes.StakeTokenConfig],
    existingStakeAccounts : AccountTypes.AccountMap,
  ) {
    private let stakeAccounts = VirtualAccounts.VirtualAccounts(existingStakeAccounts);
    private let poolAccount : Types.Account = Principal.fromText("be2us-64aaa-aaaaa-qaabq-cai");

    public func getUserAccounts() : VirtualAccounts.VirtualAccounts {
      userAccounts;
    };

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

    public func transferFromPoolToUser(
      toAccount : Types.Account,
      amount : Types.Amount,
    ) {
      stakeAccounts.transfer({
        from = poolAccount;
        to = toAccount;
        amount = amount;
      });
      unstake(toAccount, amount);
    };

    public func returnExcessTokens(
      account : Types.Account,
      amount : Types.Amount,
    ) {
      unstake(account, amount);
    };

    /**
     * Validates balances and performs the staking operations for all stake tokens.
     *
     * @param account The account performing the staking
     * @param tokenAmount The proposed token amount to stake
     * @param stakes Array of all stake token amounts
     * @returns Result with success or error
     */
    public func executeStakeTransfers(
      account : Types.Account,
      tokenAmount : Types.Amount,
      stakes : [(Types.Token, Types.Amount)],
    ) : Result.Result<(), Error.CompetitionError> {
      // Validate balance for proposed token
      switch (StakeValidation.validateStakeBalance(account, tokenAmount, userAccounts)) {
        case (#err(error)) return #err(error);
        case (#ok()) {};
      };

      // Validate balances for all stake tokens
      for ((token, amount) in stakes.vals()) {
        switch (StakeValidation.validateStakeBalance(account, amount, userAccounts)) {
          case (#err(error)) return #err(error);
          case (#ok()) {};
        };
      };

      // Perform staking for proposed token
      stake(account, tokenAmount);

      // Perform staking for all stake tokens
      for ((token, amount) in stakes.vals()) {
        stake(account, amount);
      };

      #ok(());
    };

    /**
     * Get total stake for a specific token
     */
    public func getTotalStakeForToken(token : Types.Token) : Nat {
      stakeAccounts.getTotalBalance(token).value;
    };

    /**
     * Get all total stakes for configured stake tokens
     */
    public func getAllTotalStakes() : [(Types.Token, Nat)] {
      Array.map<StakeTokenTypes.StakeTokenConfig, (Types.Token, Nat)>(
        stakeTokenConfigs,
        func(config) = (config.token, getTotalStakeForToken(config.token)),
      );
    };

    public func getStakeAccounts() : VirtualAccounts.VirtualAccounts {
      stakeAccounts;
    };

    public func getPoolAccount() : Types.Account {
      poolAccount;
    };

    public func getPoolBalance(token : Types.Token) : Types.Amount {
      stakeAccounts.getBalance(poolAccount, token);
    };
  };
};
