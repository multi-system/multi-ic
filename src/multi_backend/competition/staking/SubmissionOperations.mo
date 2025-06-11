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

/**
 * SubmissionOperations provides functions for processing, adjusting, and finalizing submissions.
 * It handles submission creation, validation, and state management.
 */
module {
  /**
   * Creates a new submission with the specified parameters.
   *
   * @param competitionEntry The competition entry for generating submission IDs
   * @param account The account creating the submission
   * @param token The token being submitted
   * @param tokenQuantity The quantity of the token
   * @param govStake The governance token stake
   * @param multiStake The multi token stake
   * @returns The newly created submission
   */
  public func createSubmission(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    account : Types.Account,
    token : Types.Token,
    tokenQuantity : Nat,
    govStake : Types.Amount,
    multiStake : Types.Amount,
  ) : SubmissionTypes.Submission {
    {
      id = competitionEntry.generateSubmissionId();
      participant = account;

      // Stake information
      govStake = govStake;
      multiStake = multiStake;

      // Token information
      token = token;

      // Initial submission
      proposedQuantity = { token = token; value = tokenQuantity };
      timestamp = Time.now();

      // Current state
      status = #Queued;
      rejectionReason = null;

      // Adjustment results after round closure
      adjustedQuantity = null;

      // Settlement results
      soldQuantity = null;
      executionPrice = null;

      // Position reference for rewards
      positionId = null;
    };
  };

  /**
   * Process a single submission using the current stake rate.
   * No stake rate recalculation is performed.
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
        submission.govStake,
        submission.multiStake,
      )
    ) {
      case (#err(error)) {
        // Submission is rejected due to validation failure
        // Create a rejected version of the submission
        let rejectedSubmission = {
          submission with
          status = #Rejected;
          rejectionReason = ?determineRejectionReason(error);
        };

        // Store the rejected submission
        competitionEntry.addSubmission(rejectedSubmission);

        return #err(error);
      };
      case (#ok(_)) {
        // Submission is valid, update status to Staked
        let activeSubmission = {
          submission with
          status = #Staked;
        };

        // Store the submission in the competition entry
        competitionEntry.addSubmission(activeSubmission);

        // Update total stakes in the entry
        competitionEntry.updateTotalStakes(
          stakeVault.getTotalGovernanceStake(),
          stakeVault.getTotalMultiStake(),
        );

        return #ok(activeSubmission);
      };
    };
  };

  /**
   * Helper function to determine the rejection reason from an error
   */
  private func determineRejectionReason(error : Error.CompetitionError) : SubmissionTypes.RejectionReason {
    switch (error) {
      case (#InsufficientStake(_)) {
        #InsufficientBalance;
      };
      case (#TokenNotApproved(_)) {
        #InvalidToken;
      };
      case (#CompetitionNotActive) {
        #CompetitionNotActive;
      };
      case (#OperationFailed(reason)) {
        #Other(reason);
      };
      case (#InvalidPhase(_)) {
        #Other("Invalid phase");
      };
      case (_) {
        #Other("Unknown error");
      };
    };
  };

  /**
   * Adjusts a submission at the end of a round by calculating the adjusted quantity based on updated stake rates.
   * Returns excess tokens to the user if necessary and updates the submission status to Finalized.
   *
   * @param competitionEntry The competition entry with configuration
   * @param stakeVault The stake vault module
   * @param submissionId The ID of the submission to adjust
   * @param updatedGovRate The adjusted governance token stake rate
   * @param updatedMultiRate The adjusted multi token stake rate
   * @returns Result with the updated submission or an error
   */
  public func adjustSubmissionPostRound(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    stakeVault : StakeVault.StakeVault,
    submissionId : SubmissionTypes.SubmissionId,
    updatedGovRate : Types.Ratio,
    updatedMultiRate : Types.Ratio,
  ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
    // Get the submission from the competition entry
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

        // Check if token is approved first
        if (not competitionEntry.isTokenApproved(submission.token)) {
          return #err(#TokenNotApproved(submission.token));
        };

        // Get token price (now returns Price directly)
        let price = competitionEntry.getCompetitionPrice(submission.token);

        // Calculate the adjusted quantity based on the adjusted stake rate
        // First, recalculate the multi stake using gov stake
        let multiStake = StakeCalculator.calculateEquivalentStake(
          submission.govStake,
          updatedGovRate,
          updatedMultiRate,
          competitionEntry.getMultiToken(),
        );

        // Then, calculate token quantity
        let rawAdjustedQuantity = StakeCalculator.calculateTokenQuantity(
          multiStake,
          updatedMultiRate,
          price,
        );

        // Trap if adjustment would increase quantity (violating design principle)
        if (rawAdjustedQuantity.value > submission.proposedQuantity.value) {
          Debug.print(
            "DIAGNOSTIC: Raw=" # debug_show (rawAdjustedQuantity.value) #
            ", Proposed=" # debug_show (submission.proposedQuantity.value)
          );
          Debug.trap("Critical error: Adjusted quantity exceeds proposed quantity - violates design principle");
        };

        let adjustedQuantity = rawAdjustedQuantity;

        // Calculate how much to return to the user - comparing Amount values now
        let excessAmount : Types.Amount = {
          token = submission.token;
          value = if (submission.proposedQuantity.value > adjustedQuantity.value) {
            submission.proposedQuantity.value - adjustedQuantity.value;
          } else {
            0;
          };
        };

        // Return excess tokens to the user if any
        if (excessAmount.value > 0) {
          // Use StakeVault's function to return excess tokens
          stakeVault.returnExcessTokens(
            submission.participant,
            excessAmount,
          );
        };

        // First remove the old submission
        ignore competitionEntry.removeSubmission(submissionId);

        // Create the updated submission
        let updatedSubmission = {
          submission with
          status = #Finalized;
          adjustedQuantity = ?{
            token = adjustedQuantity.token;
            value = adjustedQuantity.value;
          };
        };

        // Add the updated submission
        competitionEntry.addSubmission(updatedSubmission);

        return #ok(updatedSubmission);
      };
    };
  };
};
