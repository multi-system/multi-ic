import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Array "mo:base/Array";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionRegistryTypes "../types/CompetitionRegistryTypes";
import CompetitionRegistryStore "../competition/CompetitionRegistryStore";
import CompetitionManager "../competition/CompetitionManager";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import BackingTypes "../types/BackingTypes";
import SystemStakeTypes "../types/SystemStakeTypes";
import SubmissionTypes "../types/SubmissionTypes";

/**
 * CompetitionOrchestrator manages the overall lifecycle of competitions.
 * It decides when to start/end competitions and which competition should be active,
 * delegating the actual competition operations to CompetitionManager.
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

  public class CompetitionOrchestrator(
    registryStore : CompetitionRegistryStore.CompetitionRegistryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
    startSettlement : (StakingRoundOutput) -> Result.Result<(), Error.CompetitionError>,
  ) {
    // Create a single instance of the CompetitionManager to handle competition operations
    private let competitionManager = CompetitionManager.CompetitionManager(
      getCirculatingSupply,
      getBackingTokens,
      startSettlement,
    );

    /**
     * Manages the competition lifecycle based on current time.
     * This function determines which competition should be active and when transitions should occur.
     *
     * @param currentTime The current timestamp to evaluate competition states against
     */
    public func manageCompetitionLifecycle(currentTime : Time.Time) : () {
      // 1. Get Required State & Config
      let allCompetitions = registryStore.getGlobalCompetitions();
      let activeCompetitionId = registryStore.getCurrentCompetitionId();
      let globalConfig = registryStore.getGlobalConfig();
      let epochStartTime = registryStore.getEpochStartTime();

      // 2. Process Competitions in Distribution/Completed (Multiple can be in this state)
      for (comp in allCompetitions.vals()) {
        if (comp.status == #Distribution) {
          // We need a way to get entry store for non-active competitions
          switch (registryStore.getCompetitionEntryStoreById(comp.id)) {
            case (null) {
              Debug.print("Error: Cannot find entry store for competition ID " # Nat.toText(comp.id));
            };
            case (?entryStore) {
              // Calculate distribution timing
              let competitionAge = currentTime - comp.startTime;
              let distributionFrequency = globalConfig.rewardDistributionFrequency;
              let totalEvents = globalConfig.numberOfDistributionEvents;

              // Determine which distribution event we're on
              let eventIndex = competitionAge / distributionFrequency;

              // Check if it's time for a payout and we haven't exceeded total events
              // Note: Uses a 1-minute window (60B ns) which may need adjustment depending
              // on how frequently this function is called and required precision
              if (eventIndex < totalEvents and competitionAge % distributionFrequency < 60_000_000_000) {
                // Within 1 minute window of distribution time
                Debug.print(
                  "Distribution event " # Nat.toText(Int.abs(eventIndex + 1)) # " of " #
                  Nat.toText(totalEvents) # " for competition " # Nat.toText(comp.id)
                );

                // TODO: Implement actual reward distribution logic
                // This would trigger reward payments to participants
              };

              // If all distribution events completed, move to Completed state
              if (eventIndex >= totalEvents) {
                Debug.print(
                  "All distribution events completed for competition " # Nat.toText(comp.id) #
                  ", transitioning to Completed status"
                );
                entryStore.updateStatus(#Completed);
              };
            };
          };
        };
        // No specific action needed for Completed competitions
      };

      // 3. Process the Single "Active" Competition Slot
      if (activeCompetitionId == null) {
        // --- Check if it's time to start a NEW competition ---
        // Calculate when the next cycle should start
        let nextCycleStartTime = calculateNextCycleStartTime(
          epochStartTime,
          globalConfig.competitionCycleDuration,
          currentTime,
        );

        if (currentTime >= nextCycleStartTime) {
          Debug.print("Attempting to start a new competition...");

          // Create a new competition in the registry
          switch (registryStore.createCompetition()) {
            case (#err(error)) {
              Debug.print("Error creating new competition: " # debug_show (error));
            };
            case (#ok(newId)) {
              // Get the entry store for the new competition
              switch (registryStore.getCurrentCompetitionEntryStore()) {
                case (null) {
                  Debug.print("Error: Cannot find entry store for newly created competition");
                };
                case (?entryStore) {
                  // Use CompetitionManager to start the staking round
                  switch (competitionManager.startStakingRound(entryStore)) {
                    case (#ok(id)) {
                      Debug.print("Successfully started new competition ID: " # Nat.toText(id));
                    };
                    case (#err(error)) {
                      Debug.print("Error starting new competition: " # debug_show (error));
                    };
                  };
                };
              };
            };
          };
        } else {
          let timeUntilNext = nextCycleStartTime - currentTime;
          Debug.print(
            "Waiting for next competition cycle. Time until start: " #
            Nat.toText(Int.abs(timeUntilNext))
          );
        };

      } else {
        // --- Manage the CURRENT active competition ---
        let activeCompId = switch (activeCompetitionId) {
          case (?id) id;
          case (null) {
            Debug.trap("Impossible state: activeCompetitionId is both null and not null");
          };
        };

        // Find active competition in the list
        let activeCompOpt = Array.find<CompetitionEntryTypes.CompetitionEntry>(
          allCompetitions,
          func(comp) { comp.id == activeCompId },
        );

        switch (activeCompOpt) {
          case (null) {
            Debug.print("Error: Active competition ID " # Nat.toText(activeCompId) # " not found!");
            // Cannot directly set the competition ID - need to update the competition instead
            return;
          };
          case (?activeComp) {
            switch (registryStore.getCurrentCompetitionEntryStore()) {
              case (null) {
                Debug.print("Error: Cannot find entry store for active competition");
                return;
              };
              case (?activeEntryStore) {
                let currentStatus = activeEntryStore.getStatus();
                let timeInCurrentCycle = currentTime - activeComp.startTime;

                // State Transitions for the Active Competition
                if (currentStatus == #PreAnnouncement) {
                  let preAnnouncementEnd = globalConfig.preAnnouncementPeriod;
                  if (timeInCurrentCycle >= preAnnouncementEnd) {
                    Debug.print("Transitioning " # Nat.toText(activeCompId) # " to AcceptingStakes");
                    activeEntryStore.updateStatus(#AcceptingStakes);
                  } else {
                    let timeRemaining = preAnnouncementEnd - timeInCurrentCycle;
                    Debug.print(
                      "Competition " # Nat.toText(activeCompId) #
                      " in PreAnnouncement phase. Time remaining: " #
                      Nat.toText(Int.abs(timeRemaining))
                    );
                  };
                } else if (currentStatus == #AcceptingStakes) {
                  // Add buffer before cycle end to ensure time for finalization
                  let acceptingStakesEnd = globalConfig.competitionCycleDuration - 1_000_000_000;

                  if (timeInCurrentCycle >= acceptingStakesEnd) {
                    Debug.print("Attempting to end staking round for " # Nat.toText(activeCompId));

                    // Use CompetitionManager to end the staking round
                    switch (competitionManager.endStakingRound(activeEntryStore)) {
                      case (#ok(_)) {
                        Debug.print("Successfully ended staking round for " # Nat.toText(activeCompId));
                        // Competition ID is cleared automatically when status changes to Distribution
                        // No need to explicitly clear it
                      };
                      case (#err(error)) {
                        Debug.print(
                          "Error ending staking round for " # Nat.toText(activeCompId) #
                          ": " # debug_show (error)
                        );
                      };
                    };
                  } else {
                    let timeRemaining = acceptingStakesEnd - timeInCurrentCycle;
                    Debug.print(
                      "Competition " # Nat.toText(activeCompId) #
                      " accepting stakes. Time remaining: " #
                      Nat.toText(Int.abs(timeRemaining))
                    );
                  };
                } else if (currentStatus == #Finalizing or currentStatus == #Settlement) {
                  Debug.print(
                    "Warning: Competition " # Nat.toText(activeCompId) #
                    " in transient state: " # debug_show (currentStatus)
                  );
                };
                // Distribution state is handled in the first loop
              };
            };
          };
        };
      };
    }; // end manageCompetitionLifecycle

    /**
     * Calculate when the next competition cycle should start based on
     * epoch start time, cycle duration, and current time.
     */
    private func calculateNextCycleStartTime(
      epochStartTime : Time.Time,
      cycleDuration : Time.Time,
      currentTime : Time.Time,
    ) : Time.Time {
      // If current time is before epoch start, the next cycle is the epoch start
      if (currentTime < epochStartTime) {
        return epochStartTime;
      };

      // Calculate how many cycles have passed since epoch
      let timeSinceEpoch = currentTime - epochStartTime;
      let completedCycles = timeSinceEpoch / cycleDuration;

      // Next cycle starts after the current cycle completes
      let nextCycleStartTime = epochStartTime + ((completedCycles + 1) * cycleDuration);

      return nextCycleStartTime;
    };

    /**
     * Convenience function that uses the current time.
     */
    public func manageCompetitionLifecycleNow() : () {
      manageCompetitionLifecycle(Time.now());
    };
  };
};
