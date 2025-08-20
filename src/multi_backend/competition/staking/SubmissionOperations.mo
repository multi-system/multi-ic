import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";

import Types "../../types/Types";
import Error "../../error/Error";
import SubmissionTypes "../../types/SubmissionTypes";
import CompetitionEntryStore "../CompetitionEntryStore";
import StakeCalculator "./StakeCalculator";
import StakeValidation "./StakeValidation";
import StakeVault "./StakeVault";
import AmountOperations "../../financial/AmountOperations";
import TokenAccessHelper "../../helper/TokenAccessHelper";

module {
  /**
   * Creates a new submission with flexible stake tokens.
   *
   * @param competitionEntry The competition entry for generating submission IDs
   * @param account The account creating the submission
   * @param token The token being submitted
   * @param tokenQuantity The quantity of the token
   * @param stakes Array of all stake token amounts
   * @returns The newly created submission
   */
  public func createSubmission(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    account : Types.Account,
    token : Types.Token,
    tokenQuantity : Nat,
    stakes : [(Types.Token, Types.Amount)],
  ) : SubmissionTypes.Submission {
    {
      id = competitionEntry.generateSubmissionId();
      participant = account;
      stakes = stakes;
      token = token;
      proposedQuantity = { token = token; value = tokenQuantity };
      timestamp = Time.now();
      status = #Staked;
      rejectionReason = null;
      adjustedQuantity = null;
      soldQuantity = null;
      executionPrice = null;
      positionId = null;
    };
  };

  /**
   * Process a submission with flexible stake tokens.
   *
   * @param competitionEntry The competition entry with configuration
   * @param stakeVault The stake vault module
   * @param submission The submission to process
   * @returns Result indicating success or rejection reason
   */
  public func processSubmission(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    stakeVault : StakeVault.StakeVault,
    submission : SubmissionTypes.Submission,
  ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {

    // Validate competition state
    if (competitionEntry.getStatus() != #AcceptingStakes) {
      return #err(#InvalidPhase({ current = debug_show (competitionEntry.getStatus()); required = "AcceptingStakes" }));
    };

    // Perform staking through StakeVault
    switch (
      stakeVault.executeStakeTransfers(
        submission.participant,
        submission.proposedQuantity,
        submission.stakes,
      )
    ) {
      case (#err(error)) {
        let rejectedSubmission = {
          submission with
          status = #Rejected;
          rejectionReason = ?determineRejectionReason(error);
        };
        competitionEntry.addSubmission(rejectedSubmission);
        return #err(error);
      };
      case (#ok(_)) {
        // Store the submission
        competitionEntry.addSubmission(submission);

        // Update total stakes for all stake tokens
        for ((token, amount) in submission.stakes.vals()) {
          ignore competitionEntry.addToTotalStake(token, amount.value);
        };

        return #ok(submission);
      };
    };
  };

  private func determineRejectionReason(error : Error.CompetitionError) : SubmissionTypes.RejectionReason {
    switch (error) {
      case (#InsufficientStake(_)) { #InsufficientBalance };
      case (#TokenNotApproved(_)) { #InvalidToken };
      case (#CompetitionNotActive) { #CompetitionNotActive };
      case (#OperationFailed(reason)) { #Other(reason) };
      case (#InvalidPhase(_)) { #Other("Invalid phase") };
      case (_) { #Other("Unknown error") };
    };
  };

  /**
   * Adjusts a submission at the end of a round with flexible stake tokens.
   *
   * @param competitionEntry The competition entry with configuration
   * @param stakeVault The stake vault module
   * @param submissionId The ID of the submission to adjust
   * @param updatedRates Array of updated rates for all stake tokens
   * @returns Result with the updated submission or an error
   */
  public func adjustSubmissionPostRound(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    stakeVault : StakeVault.StakeVault,
    submissionId : SubmissionTypes.SubmissionId,
    updatedRates : [(Types.Token, Types.Ratio)],
  ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {

    let submissionOpt = competitionEntry.getSubmission(submissionId);

    switch (submissionOpt) {
      case (null) {
        return #err(#OperationFailed("Submission not found with ID: " # debug_show (submissionId)));
      };
      case (?submission) {
        // Skip submissions that are not in Staked status
        if (submission.status != #Staked) {
          return #err(#InvalidPhase({ current = debug_show (submission.status); required = "Staked" }));
        };

        // Check if token is approved
        if (not competitionEntry.isTokenApproved(submission.token)) {
          return #err(#TokenNotApproved(submission.token));
        };

        let price = competitionEntry.getCompetitionPrice(submission.token);

        // Use any stake token for calculation (they're all equivalent due to rates)
        // We'll use the first one for simplicity
        if (submission.stakes.size() == 0) {
          return #err(#InvalidSubmission({ reason = "No stakes in submission" }));
        };

        let (calcToken, calcStake) = submission.stakes[0];

        // Find the updated rate for the calculation token
        let calcRateOpt = TokenAccessHelper.findInTokenArray(updatedRates, calcToken);

        let calcRate = switch (calcRateOpt) {
          case (null) {
            Debug.trap("Stake token rate not found in updated rates");
          };
          case (?rate) { rate };
        };

        // Calculate adjusted quantity
        let rawAdjustedQuantity = StakeCalculator.calculateTokenQuantity(
          calcStake,
          calcRate,
          price,
        );

        // Ensure adjustment doesn't increase quantity
        if (rawAdjustedQuantity.value > submission.proposedQuantity.value) {
          Debug.trap("Critical error: Adjusted quantity exceeds proposed quantity");
        };

        let adjustedQuantity = rawAdjustedQuantity;

        // Calculate excess to return
        let excessAmount : Types.Amount = {
          token = submission.token;
          value = if (submission.proposedQuantity.value > adjustedQuantity.value) {
            submission.proposedQuantity.value - adjustedQuantity.value;
          } else { 0 };
        };

        // Return excess tokens if any
        if (excessAmount.value > 0) {
          stakeVault.returnExcessTokens(submission.participant, excessAmount);
        };

        // Remove old submission
        ignore competitionEntry.removeSubmission(submissionId);

        // Create and add updated submission
        let updatedSubmission = {
          submission with
          status = #Finalized;
          adjustedQuantity = ?{
            token = adjustedQuantity.token;
            value = adjustedQuantity.value;
          };
        };

        competitionEntry.addSubmission(updatedSubmission);

        return #ok(updatedSubmission);
      };
    };
  };
};
