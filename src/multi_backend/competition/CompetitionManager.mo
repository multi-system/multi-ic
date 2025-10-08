import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import CompetitionEntryStore "../competition/CompetitionEntryStore";
import StakingManager "./staking/StakingManager";
import DistributionCoordinator "./distribution/DistributionCoordinator";
import BackingTypes "../types/BackingTypes";
import SubmissionTypes "../types/SubmissionTypes";
import FinalizeStakingRound "./staking/FinalizeStakingRound";
import SystemStakeTypes "../types/SystemStakeTypes";
import VirtualAccounts "../custodial/VirtualAccounts";

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
    adjustedRates : [(Types.Token, Types.Ratio)];
    volumeLimit : Nat;
  };

  public class CompetitionManager(
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
    startSettlement : (StakingRoundOutput) -> Result.Result<(), Error.CompetitionError>,
    getUserAccounts : () -> VirtualAccounts.VirtualAccounts,
    getSystemAccount : () -> Types.Account,
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
     * Creates a DistributionCoordinator for the specified competition.
     * Reuses the cached dependencies for efficiency.
     */
    private func createDistributionCoordinator(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : DistributionCoordinator.DistributionCoordinator {
      DistributionCoordinator.DistributionCoordinator(
        getUserAccounts(),
        getSystemAccount(),
        entryStore.getConfig().stakeTokenConfigs,
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
      // Add logging to track state when method is called
      let status = entryStore.getStatus();
      Debug.print(
        "CompetitionManager.endStakingRound: Competition #" # Nat.toText(entryStore.getId()) #
        " current status: " # debug_show (status)
      );

      // This method is called by the orchestrator, so we trap on unexpected state
      // since it would indicate a bug in the orchestration logic
      if (status != #AcceptingStakes) {
        Debug.trap("Critical error: Cannot end staking round for competition not in AcceptingStakes state. Current state: " # debug_show (status));
      };

      // Create the staking manager for this competition
      let stakingManager = createStakingManager(entryStore);

      switch (stakingManager.finalizeRound()) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok(result)) {
          // NOW update competition status to Finalizing, then Settlement, then Distribution
          // This ensures all staking operations complete while still in AcceptingStakes
          entryStore.updateStatus(#Finalizing);
          entryStore.updateStatus(#Settlement);

          // Prepare data for settlement phase
          let stakingOutput : StakingRoundOutput = {
            finalizedSubmissions = entryStore.getSubmissionsByStatus(#Finalized);
            systemStake = result.systemStake;
            adjustedRates = result.finalRates;
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
     * Process a distribution event for a competition.
     * This distributes rewards to participants based on performance.
     *
     * @param entryStore The entry store for the competition
     * @param distributionNumber The distribution event number (0-based)
     * @param distributionEvent The distribution event details
     * @return Result indicating success or error
     */
    public func processDistribution(
      entryStore : CompetitionEntryStore.CompetitionEntryStore,
      distributionNumber : Nat,
      distributionEvent : CompetitionEntryTypes.DistributionEvent,
    ) : Result.Result<(), Error.CompetitionError> {
      // This method is called by the orchestrator, so we trap on unexpected state
      let status = entryStore.getStatus();
      if (status != #Distribution) {
        Debug.trap("Critical error: Cannot process distribution for competition not in Distribution state. Current state: " # debug_show (status));
      };

      // Verify this is the expected distribution number
      let expectedNumber = switch (entryStore.getLastDistributionIndex()) {
        case (null) { 0 };
        case (?lastIndex) { lastIndex + 1 };
      };

      if (distributionNumber != expectedNumber) {
        Debug.trap("Critical error: Distribution number mismatch. Expected: " # Nat.toText(expectedNumber) # ", Got: " # Nat.toText(distributionNumber));
      };

      Debug.print("Processing distribution #" # Nat.toText(distributionNumber + 1) # " for competition " # Nat.toText(entryStore.getId()));
      Debug.print("Distribution event uses price event #" # Nat.toText(distributionEvent.distributionPrices));

      // Create the coordinator and process the distribution
      let coordinator = createDistributionCoordinator(entryStore);

      switch (coordinator.processDistribution(entryStore, distributionNumber, distributionEvent)) {
        case (#err(e)) {
          Debug.print("Error processing distribution: " # debug_show (e));
          return #err(#OperationFailed("Distribution processing failed"));
        };
        case (#ok(_)) {
          Debug.print("Successfully processed distribution");
          #ok();
        };
      };
    };

    /**
     * End a competition and perform final cleanup.
     *
     * @param entryStore The entry store for the competition to end
     * @return Result indicating success or error
     */
    public func endCompetition(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : Result.Result<(), Error.CompetitionError> {
      // This method is called by the orchestrator, so we trap on unexpected state
      let status = entryStore.getStatus();
      if (status != #Distribution) {
        Debug.trap("Critical error: Cannot end competition not in Distribution state. Current state: " # debug_show (status));
      };

      // Verify all distributions have been completed
      let config = entryStore.getConfig();
      let lastDistribution = entryStore.getLastDistributionIndex();

      switch (lastDistribution) {
        case (null) {
          Debug.trap("Critical error: No distributions have been processed");
        };
        case (?index) {
          // Index is 0-based, so we need index + 1 to equal numberOfDistributionEvents
          if (index + 1 < config.numberOfDistributionEvents) {
            Debug.trap("Critical error: Not all distributions completed. Processed: " # Nat.toText(index + 1) # ", Required: " # Nat.toText(config.numberOfDistributionEvents));
          };
        };
      };

      // Update status to Completed
      entryStore.updateStatus(#Completed);

      Debug.print("Competition " # Nat.toText(entryStore.getId()) # " has been completed");

      // TODO: Any final cleanup logic could go here
      // For example:
      // - Final stake reconciliation
      // - Archiving competition data
      // - Releasing any locked resources

      #ok(());
    };
  };
};
