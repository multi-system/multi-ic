import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Array "mo:base/Array";

import Types "../../types/Types";
import Error "../../error/Error";
import BackingTypes "../../types/BackingTypes";
import CompetitionStore "../CompetitionStore";
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
    store : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) {
    // Create a submission using SubmissionOperations - now with store parameter
    private func createSubmission(
      account : Types.Account,
      quantities : SubmissionQuantities,
      token : Types.Token,
    ) : SubmissionTypes.Submission {
      SubmissionOperations.createSubmission(
        store,
        account,
        token,
        quantities.tokenQuantity.value,
        quantities.govStake,
        quantities.multiStake,
      );
    };

    // Queue a submission for later processing
    public func queueSubmission(
      account : Types.Account,
      quantities : SubmissionQuantities,
      token : Types.Token,
    ) : SubmissionTypes.SubmissionId {
      let submission = createSubmission(account, quantities, token);

      // Create a submission in PreRound status (effectively queued)
      let queuedSubmission = {
        submission with
        status = #PreRound;
      };

      // Add to store
      store.addSubmission(queuedSubmission);

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
      switch (StakeOperations.calculateSubmission(store, govStake, proposedToken)) {
        case (#err(e)) return #err(e);
        case (#ok(quantities)) {
          if (shouldQueue) {
            // Add to queue as PreRound submission
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
            switch (SubmissionOperations.processSubmission(store, stakeVault, submission)) {
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
      // Get all queued submissions as a stable array copy
      let queuedSubmissions = Array.freeze<SubmissionTypes.Submission>(
        Array.thaw<SubmissionTypes.Submission>(store.getSubmissionsByStatus(#PreRound))
      );

      // Process each queued submission from our stable copy
      for (i in queuedSubmissions.keys()) {
        let submission = queuedSubmissions[i];

        // First remove the submission from the store to avoid duplication
        store.removeSubmission(submission.id);

        // Process using SubmissionOperations
        switch (SubmissionOperations.processSubmission(store, stakeVault, submission)) {
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

    // Get all queued submissions
    public func getQueuedSubmissions() : [SubmissionTypes.Submission] {
      store.getSubmissionsByStatus(#PreRound);
    };

    // Get number of queued submissions
    public func getQueueSize() : Nat {
      store.getSubmissionCountByStatus(#PreRound);
    };

    // Finalize a single submission (for testing)
    public func finalizeSubmission(
      submissionId : SubmissionTypes.SubmissionId,
      updatedGovRate : Types.Ratio,
      updatedMultiRate : Types.Ratio,
    ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
      SubmissionOperations.adjustSubmissionPostRound(
        store,
        stakeVault,
        submissionId,
        updatedGovRate,
        updatedMultiRate,
      );
    };
  };
};
