import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Int "mo:base/Int";

import Types "../types/Types";
import Error "../error/Error";
import BackingTypes "../types/BackingTypes";
import CompetitionStore "./CompetitionStore";
import StakeVault "./staking/StakeVault";
import FinalizeStakingRound "./staking/FinalizeStakingRound";
import StakingManager "./staking/StakingManager";
import CompetitionTypes "../types/CompetitionTypes";
import SubmissionTypes "../types/SubmissionTypes";
import SystemStakeTypes "../types/SystemStakeTypes";

/**
 * CompetitionAutomation handles the automated lifecycle of competitions.
 * It provides a single function to check if state should change based on timing.
 */
module {
  // Simple tracking of competition cycle
  public type AutomationState = {
    var lastStateChangeTime : Time.Time;
    var currentCycleIndex : Nat;
  };

  // Configuration for competition timing
  public type AutomationConfig = {
    activeTime : Nat; // Duration in nanoseconds when competition is active
    pauseTime : Nat; // Duration in nanoseconds between competitions
  };

  // Type for the settlement initiator function
  public type SettlementInitiator = (
    output : {
      finalizedSubmissions : [SubmissionTypes.Submission];
      systemStake : SystemStakeTypes.SystemStake;
      govRate : Types.Ratio;
      multiRate : Types.Ratio;
      volumeLimit : Nat;
    }
  ) -> Result.Result<(), Error.CompetitionError>;

  public class CompetitionAutomation(
    compStore : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    stakingManager : StakingManager.StakingManager,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
    startSettlement : ?SettlementInitiator,
    initialConfig : AutomationConfig,
  ) {
    private var config : AutomationConfig = initialConfig;

    private let state : AutomationState = {
      var lastStateChangeTime = Time.now();
      var currentCycleIndex = 0;
    };

    // Get current state (for tests and monitoring)
    public func getState() : AutomationState {
      state;
    };

    // Get the current configuration
    public func getConfig() : AutomationConfig {
      config;
    };

    // Update competition timing configuration
    public func updateConfig(newConfig : AutomationConfig) : () {
      config := newConfig;
    };

    /**
     * Primary function that checks if state should change and applies the change if needed.
     * Takes current time as a parameter to make it testable.
     *
     * @param currentTime The current time to check against (for testing)
     */
    public func checkAndUpdateCompetitionState(currentTime : Time.Time) : async () {
      let isCurrentlyActive = compStore.isCompetitionActive();
      let timeSinceLastChange = currentTime - state.lastStateChangeTime;

      if (isCurrentlyActive) {
        // Check if active staking round should end
        if (timeSinceLastChange >= config.activeTime) {
          Debug.print("Ending staking round: cycle #" # debug_show (state.currentCycleIndex));

          // Process all queued submissions
          stakingManager.processQueue();

          // Finalize staking round
          switch (await finalizeCurrentStakingRound()) {
            case (#err(e)) {
              Debug.print("Error finalizing staking round: " # debug_show (e));
            };
            case (#ok(result)) {
              // Update state tracking
              state.lastStateChangeTime := currentTime;
              compStore.setCompetitionActive(false);

              // Prepare data for settlement phase
              let stakingOutput = {
                finalizedSubmissions = compStore.getSubmissionsByStatus(#PostRound);
                systemStake = result.systemStake;
                govRate = result.finalGovRate;
                multiRate = result.finalMultiRate;
                volumeLimit = result.volumeLimit;
              };

              // Start settlement if initiator is provided
              switch (startSettlement) {
                case (null) {
                  // No settlement initiator provided
                  Debug.print("Staking round ended successfully, but no settlement initiator provided");
                };
                case (?initiator) {
                  // Start settlement
                  switch (initiator(stakingOutput)) {
                    case (#err(e)) {
                      Debug.print("Error starting settlement: " # debug_show (e));
                    };
                    case (#ok(_)) {
                      Debug.print("Settlement started successfully");
                    };
                  };
                };
              };

              Debug.print("Staking round ended successfully");
            };
          };
        };
      } else {
        // Check if a new staking round should start
        if (timeSinceLastChange >= config.pauseTime) {
          // Start a new staking round
          Debug.print("Starting staking round: cycle #" # Int.toText(state.currentCycleIndex + 1));

          compStore.setCompetitionActive(true);
          state.lastStateChangeTime := currentTime;
          state.currentCycleIndex += 1;
        };
      };
    };

    /**
     * Convenience wrapper that uses the current system time.
     * This is the function that would normally be called by a heartbeat.
     */
    public func checkAndUpdateCompetitionStateNow() : async () {
      await checkAndUpdateCompetitionState(Time.now());
    };

    // Helper function to finalize a staking round
    private func finalizeCurrentStakingRound() : async Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      FinalizeStakingRound.finalizeRound(
        compStore,
        stakeVault,
        getCirculatingSupply,
        getBackingTokens,
      );
    };
  };
};
