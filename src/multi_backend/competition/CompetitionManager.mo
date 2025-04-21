import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import CompetitionEntryStore "../competition/CompetitionEntryStore";
import StakingManager "./staking/StakingManager";
import BackingTypes "../types/BackingTypes";
import SubmissionTypes "../types/SubmissionTypes";
import FinalizeStakingRound "./staking/FinalizeStakingRound";
import SystemStakeTypes "../types/SystemStakeTypes";

/**
 * CompetitionManager handles operations for individual competitions.
 * It delegates to StakingManager for staking operations and maintains
 * references to shared resources for efficiency.
 */
module {
  // Define the output type for staking rounds
  public type StakingRoundOutput = {
    finalizedSubmissions : [SubmissionTypes.Submission];
    systemStake : SystemStakeTypes.SystemStake;
    govRate : Types.Ratio;
    multiRate : Types.Ratio;
    volumeLimit : Nat;
  };

  public class CompetitionManager(
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
    startSettlement : (StakingRoundOutput) -> Result.Result<(), Error.CompetitionError>,
  ) {
    /**
     * Starts a staking round for a specific competition.
     * Transitions from PreAnnouncement to AcceptingStakes.
     *
     * @param entryStore The entry store for the competition to start
     * @return Result with competition ID or error
     */
    public func startStakingRound(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : Result.Result<Nat, Error.CompetitionError> {
      // This method is called by the orchestrator, so we trap on unexpected state
      // since it would indicate a bug in the orchestration logic
      let status = entryStore.getStatus();
      if (status != #PreAnnouncement) {
        Debug.trap("Critical error: Cannot start staking round for competition not in PreAnnouncement state. Current state: " # debug_show (status));
      };

      // Update the competition status to AcceptingStakes
      entryStore.updateStatus(#AcceptingStakes);
      return #ok(entryStore.getId());
    };

    /**
     * Creates a StakingManager for the specified competition.
     * Reuses the cached dependencies for efficiency.
     */
    private func createStakingManager(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : StakingManager.StakingManager {
      StakingManager.StakingManager(
        entryStore,
        getCirculatingSupply,
        getBackingTokens,
      );
    };

    /**
     * Ends the staking round for a specific competition.
     * Handles finalization, settlement, and transitions to Distribution phase.
     *
     * @param entryStore The entry store for the competition to end
     * @return Result with finalization results or error
     */
    public func endStakingRound(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      // This method is called by the orchestrator, so we trap on unexpected state
      // since it would indicate a bug in the orchestration logic
      let status = entryStore.getStatus();
      if (status != #AcceptingStakes) {
        Debug.trap("Critical error: Cannot end staking round for competition not in AcceptingStakes state. Current state: " # debug_show (status));
      };

      // Update competition status to Finalizing
      entryStore.updateStatus(#Finalizing);

      // Create the staking manager for this competition
      let stakingManager = createStakingManager(entryStore);

      // Process all queued submissions first
      stakingManager.processQueue();

      // Then finalize all submissions
      switch (stakingManager.finalizeRound()) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok(result)) {
          // Mark the competition as in Settlement phase
          entryStore.updateStatus(#Settlement);

          // Prepare data for settlement phase
          let stakingOutput : StakingRoundOutput = {
            finalizedSubmissions = entryStore.getSubmissionsByStatus(#Finalized);
            systemStake = result.systemStake;
            govRate = result.finalGovRate;
            multiRate = result.finalMultiRate;
            volumeLimit = result.volumeLimit;
          };

          // Start settlement and handle the result
          switch (startSettlement(stakingOutput)) {
            case (#err(e)) {
              Debug.print("Error starting settlement: " # debug_show (e));
              return #err(e);
            };
            case (#ok(_)) {
              Debug.print("Settlement started successfully");

              // Move to Distribution phase after settlement is started
              entryStore.updateStatus(#Distribution);
            };
          };

          #ok(result);
        };
      };
    };

    /**
     * Process all queued submissions for a competition.
     *
     * @param entryStore The entry store for the competition
     */
    public func processQueue(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : () {
      // Queue processing should only happen in the AcceptingStakes phase
      // Trap if called in any other state as it indicates a system bug
      let status = entryStore.getStatus();
      if (status != #AcceptingStakes) {
        Debug.trap("Critical error: Cannot process queue for competition not in AcceptingStakes state. Current state: " # debug_show (status));
      };

      // Create the staking manager and process the queue
      let stakingManager = createStakingManager(entryStore);
      stakingManager.processQueue();
    };

    /**
     * Accept a stake request for a specific competition.
     * This method handles user input, so it returns errors rather than trapping.
     *
     * @param entryStore The entry store for the competition
     * @param govStake The governance token stake
     * @param account The account making the stake
     * @param proposedToken The token being proposed
     * @param shouldQueue Whether to queue the submission
     * @return Result with submission details or error
     */
    public func acceptStakeRequest(
      entryStore : CompetitionEntryStore.CompetitionEntryStore,
      govStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
      shouldQueue : Bool,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount; isQueued : Bool }, Error.CompetitionError> {
      // Validate the competition is in the right state
      // This method handles user input, so return error instead of trapping
      if (entryStore.getStatus() != #AcceptingStakes) {
        return #err(#InvalidPhase({ current = debug_show (entryStore.getStatus()); required = "AcceptingStakes" }));
      };

      // Create the staking manager and process the stake request
      let stakingManager = createStakingManager(entryStore);
      stakingManager.acceptStakeRequest(govStake, account, proposedToken, shouldQueue);
    };
  };
};
