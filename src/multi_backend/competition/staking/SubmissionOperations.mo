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
import CompetitionStore "../CompetitionStore";
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
   * @param store The competition store for generating submission IDs
   * @param account The account creating the submission
   * @param token The token being submitted
   * @param tokenQuantity The quantity of the token
   * @param govStake The governance token stake
   * @param multiStake The multi token stake
   * @returns The newly created submission
   */
  public func createSubmission(
    store : CompetitionStore.CompetitionStore,
    account : Types.Account,
    token : Types.Token,
    tokenQuantity : Nat,
    govStake : Types.Amount,
    multiStake : Types.Amount,
  ) : SubmissionTypes.Submission {
    {
      id = store.generateSubmissionId();
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
      status = #PreRound;
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
   * @param store The competition store with configuration
   * @param stakeVault The stake vault module
   * @param submission The submission to process
   * @returns Result indicating success or rejection reason
   */
  public func processSubmission(
    store : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    submission : SubmissionTypes.Submission,
  ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
    // Validate competition state - these conditions should never occur in production
    if (not store.hasInitialized()) {
      Debug.trap("Competition system not initialized - critical invariant violation");
    };

    if (not store.isCompetitionActive()) {
      Debug.trap("Competition not active - processSubmission called in wrong phase");
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
        store.addSubmission(rejectedSubmission);

        return #err(error);
      };
      case (#ok(_)) {
        // Submission is valid, update status to ActiveRound
        let activeSubmission = {
          submission with
          status = #ActiveRound;
        };

        // Store the submission in the competition store
        store.addSubmission(activeSubmission);

        // Update total stakes in the store
        store.updateTotalStakes(
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
   * Returns excess tokens to the user if necessary and updates the submission status to PostRound.
   *
   * @param store The competition store with configuration
   * @param stakeVault The stake vault module
   * @param submissionId The ID of the submission to adjust
   * @param updatedGovRate The adjusted governance token stake rate
   * @param updatedMultiRate The adjusted multi token stake rate
   * @returns Result with the updated submission or an error
   */
  public func adjustSubmissionPostRound(
    store : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    submissionId : SubmissionTypes.SubmissionId,
    updatedGovRate : Types.Ratio,
    updatedMultiRate : Types.Ratio,
  ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
    // Get the submission directly from the store
    let submissionOpt = store.getSubmission(submissionId);

    switch (submissionOpt) {
      case (null) {
        Debug.trap("Critical error: Submission not found - system state inconsistency detected");
      };
      case (?submission) {
        // Skip submissions that are not in ActiveRound status
        if (submission.status != #ActiveRound) {
          return #err(#InvalidPhase({ current = debug_show (submission.status); required = "ActiveRound" }));
        };

        // Get token price
        let price = switch (store.getCompetitionPrice(submission.token)) {
          case (null) {
            return #err(#TokenNotApproved(submission.token));
          };
          case (?p) { p };
        };

        // Calculate the adjusted quantity based on the adjusted stake rate
        // First, recalculate the multi stake using gov stake
        let multiStake = StakeCalculator.calculateEquivalentStake(
          submission.govStake,
          updatedGovRate,
          updatedMultiRate,
          store.getMultiToken(),
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
        store.removeSubmission(submissionId);

        // Create the updated submission
        let updatedSubmission = {
          submission with
          status = #PostRound;
          adjustedQuantity = ?{
            token = adjustedQuantity.token;
            value = adjustedQuantity.value;
          };
        };

        // Add the updated submission
        store.addSubmission(updatedSubmission);

        return #ok(updatedSubmission);
      };
    };
  };
};
