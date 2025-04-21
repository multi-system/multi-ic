import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Array "mo:base/Array";

import Types "../../types/Types";
import Error "../../error/Error";
import BackingTypes "../../types/BackingTypes";
import CompetitionEntryStore "../CompetitionEntryStore";
import SubmissionTypes "../../types/SubmissionTypes";
import StakeOperations "./StakeOperations";
import StakeVault "./StakeVault";
import SubmissionOperations "./SubmissionOperations";
import FinalizeStakingRound "./FinalizeStakingRound";

module {
  /**
   * Helper type for submission quantities
   */
  public type SubmissionQuantities = {
    tokenQuantity : Types.Amount;
    govStake : Types.Amount;
    multiStake : Types.Amount;
  };

  public class StakingManager(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) {
    // Get the StakeVault from the competition entry
    private func getStakeVault() : StakeVault.StakeVault {
      competitionEntry.getStakeVault();
    };

    // Create a submission using SubmissionOperations
    private func createSubmission(
      account : Types.Account,
      quantities : SubmissionQuantities,
      token : Types.Token,
    ) : SubmissionTypes.Submission {
      SubmissionOperations.createSubmission(
        competitionEntry,
        account,
        token,
        quantities.tokenQuantity.value,
        quantities.govStake,
        quantities.multiStake,
      );
    };

    // Track queuedSubmissionIds to handle removal properly
    private var queuedSubmissionIds = Buffer.Buffer<SubmissionTypes.SubmissionId>(10);

    // Queue a submission for later processing
    public func queueSubmission(
      account : Types.Account,
      quantities : SubmissionQuantities,
      token : Types.Token,
    ) : SubmissionTypes.SubmissionId {
      let submission = createSubmission(account, quantities, token);

      // Create a submission in Queued status
      let queuedSubmission = {
        submission with
        status = #Queued;
      };

      // Add to both competitionEntry for test visibility and track ID locally
      competitionEntry.addSubmission(queuedSubmission);
      queuedSubmissionIds.add(submission.id);

      submission.id;
    };

    // Handle stake requests - calculate, then process or queue
    public func acceptStakeRequest(
      govStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
      shouldQueue : Bool,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount; isQueued : Bool }, Error.CompetitionError> {
      // Calculate the submission quantities using StakeOperations
      switch (StakeOperations.calculateSubmission(competitionEntry, govStake, proposedToken)) {
        case (#err(e)) return #err(e);
        case (#ok(quantities)) {
          if (shouldQueue) {
            // Add to queue as Queued submission
            let submissionId = queueSubmission(account, quantities, proposedToken);

            #ok({
              submissionId;
              tokenQuantity = quantities.tokenQuantity;
              isQueued = true;
            });
          } else {
            // Create a submission object for direct processing
            let submission = createSubmission(account, quantities, proposedToken);

            // Process directly using SubmissionOperations
            switch (SubmissionOperations.processSubmission(competitionEntry, getStakeVault(), submission)) {
              case (#err(e)) return #err(e);
              case (#ok(_)) {
                #ok({
                  submissionId = submission.id;
                  tokenQuantity = quantities.tokenQuantity;
                  isQueued = false;
                });
              };
            };
          };
        };
      };
    };

    // Process all queued submissions one by one
    public func processQueue() : () {
      let currentQueue = Buffer.toArray(queuedSubmissionIds);
      queuedSubmissionIds.clear();

      // Process each queued submission
      for (submissionId in currentQueue.vals()) {
        // Get the submission from the store
        switch (competitionEntry.getSubmission(submissionId)) {
          case (null) {
            Debug.trap("Critical error: Queued submission not found: " # debug_show (submissionId));
          };
          case (?submission) {
            // Remove from store first to avoid accounting issues
            ignore competitionEntry.removeSubmission(submissionId);

            // Process using SubmissionOperations
            switch (SubmissionOperations.processSubmission(competitionEntry, getStakeVault(), submission)) {
              case (#ok(_)) {
                // Successfully processed
              };
              case (#err(error)) {
                // Failure to process a submission is catastrophic for a financial system
                Debug.trap(
                  "Fatal error: Failed to process submission ID: " # debug_show (submission.id) #
                  " - Error: " # debug_show (error)
                );
              };
            };
          };
        };
      };
    };

    // Get all queued submissions
    public func getQueuedSubmissions() : [SubmissionTypes.Submission] {
      competitionEntry.getSubmissionsByStatus(#Queued);
    };

    // Get number of queued submissions
    public func getQueueSize() : Nat {
      competitionEntry.getSubmissionCountByStatus(#Queued);
    };

    // Finalize a single submission (for testing)
    public func finalizeSubmission(
      submissionId : SubmissionTypes.SubmissionId,
      updatedGovRate : Types.Ratio,
      updatedMultiRate : Types.Ratio,
    ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
      SubmissionOperations.adjustSubmissionPostRound(
        competitionEntry,
        getStakeVault(),
        submissionId,
        updatedGovRate,
        updatedMultiRate,
      );
    };

    // Finalize the current staking round
    public func finalizeRound() : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      FinalizeStakingRound.finalizeRound(
        competitionEntry,
        getCirculatingSupply,
        getBackingTokens,
      );
    };
  };
};
