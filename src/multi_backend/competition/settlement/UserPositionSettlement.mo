import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Map "mo:base/HashMap";
import Text "mo:base/Text";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import SubmissionTypes "../../types/SubmissionTypes";
import TransferTypes "../../types/TransferTypes";
import VirtualAccounts "../../custodial/VirtualAccounts";
import VirtualAccountBridge "../../custodial/VirtualAccountBridge";
import RatioOperations "../../financial/RatioOperations";

/**
 * Handles the settlement of user submissions by transferring tokens
 * from stake accounts to the system and transferring Multi tokens to users.
 */
module {
  public class UserPositionSettlement(
    userAccounts : VirtualAccounts.VirtualAccounts,
    stakeAccounts : VirtualAccounts.VirtualAccounts,
    multiToken : Types.Token,
    systemAccount : Types.Account,
  ) {
    /**
     * Settles a user submission by transferring tokens and distributing Multi tokens.
     * Creates and returns a RewardTypes.Position for tracking performance.
     *
     * @param submission The finalized submission to settle
     * @param price The execution price for the token
     * @param submissionValue The calculated Multi value for this submission
     * @param totalValue The total calculated value for all submissions
     * @param mintedAmount The total amount of Multi minted for acquisitions
     * @returns A RewardTypes.Position with settlement details
     */
    public func settleUserSubmission(
      submission : SubmissionTypes.Submission,
      price : Types.Price,
      submissionValue : Nat,
      totalValue : Nat,
      mintedAmount : Types.Amount,
    ) : RewardTypes.Position {
      // Verify submission is finalized and has adjusted quantity
      if (submission.status != #Finalized or submission.adjustedQuantity == null) {
        Debug.trap(
          "Critical error: Attempted to settle submission " #
          debug_show (submission.id) # " with invalid status " #
          debug_show (submission.status) # " or missing adjustedQuantity"
        );
      };

      // Properly unwrap the optional value
      let tokenAmount = switch (submission.adjustedQuantity) {
        case (null) {
          Debug.trap("Critical error: Adjusted quantity is null even though we already checked it");
        };
        case (?amount) {
          amount;
        };
      };

      // Verify price is for the correct token
      if (not Principal.equal(price.baseToken, tokenAmount.token)) {
        Debug.trap(
          "Critical error: Token mismatch in submission " #
          debug_show (submission.id) # ": submission token " #
          Principal.toText(tokenAmount.token) # " doesn't match price token " #
          Principal.toText(price.baseToken)
        );
      };

      // Calculate user's share of the minted tokens
      let shareFraction = RatioOperations.fromNats(submissionValue, totalValue);
      let userMultiAmount = RatioOperations.applyToAmount(mintedAmount, shareFraction);

      // Transfer tokens from stake account to user account
      // This correctly uses VirtualAccountBridge.transfer as it's moving tokens
      // between different account systems for the same user
      VirtualAccountBridge.transfer(
        stakeAccounts,
        userAccounts,
        submission.participant,
        tokenAmount,
      );

      // Then from user account to system account
      // For transfers between different accounts in the same system,
      // use userAccounts.transfer directly
      let transferArgs1 : TransferTypes.TransferArgs = {
        from = submission.participant;
        to = systemAccount;
        amount = tokenAmount;
      };
      userAccounts.transfer(transferArgs1);

      // Only transfer Multi tokens if the amount is greater than zero
      if (userMultiAmount.value > 0) {
        // Transfer Multi tokens from system account to the user
        // Also a transfer between different accounts in the same system
        let transferArgs2 : TransferTypes.TransferArgs = {
          from = systemAccount;
          to = submission.participant;
          amount = userMultiAmount;
        };
        userAccounts.transfer(transferArgs2);
      };

      // Create and return a Position for reward tracking
      {
        quantity = tokenAmount;
        govStake = submission.govStake;
        multiStake = submission.multiStake;
        submissionId = ?submission.id;
        isSystem = false;
        distributionPayouts = [];
      };
    };
  };
};
