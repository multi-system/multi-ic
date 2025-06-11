import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Option "mo:base/Option";

import CompetitionRegistryStore "./CompetitionRegistryStore";
import CompetitionManager "./CompetitionManager";
import CompetitionStateMachine "./CompetitionStateMachine";
import EventManager "./EventManager";
import EventTypes "../types/EventTypes";
import Types "../types/Types";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";

module {
  public class CompetitionOrchestrator(
    registryStore : CompetitionRegistryStore.CompetitionRegistryStore,
    eventManager : EventManager.EventManager,
    competitionManager : CompetitionManager.CompetitionManager,
  ) {
    // Track the current price event for this heartbeat
    private var currentHeartbeatPriceEvent : ?Nat = null;

    /**
     * Main heartbeat function called periodically to manage all competitions
     *
     * @param currentTime Current timestamp to use for evaluation
     */
    public func heartbeat(currentTime : Time.Time) : () {
      // 1. Always record a heartbeat event
      let heartbeatId = eventManager.recordHeartbeat(currentTime);
      Debug.print("Recorded heartbeat #" # Nat.toText(heartbeatId) # " at " # Int.toText(currentTime));

      // Reset price event tracking for new heartbeat
      currentHeartbeatPriceEvent := null;

      // 2. Process all competitions
      let allCompetitions = registryStore.getGlobalCompetitions();
      var shouldCreateNewCompetition = false;

      Debug.print("Processing " # Nat.toText(allCompetitions.size()) # " competitions");

      for (competition in allCompetitions.vals()) {
        Debug.print("Checking competition #" # Nat.toText(competition.id) # " with status: " # debug_show (competition.status));

        // Check what action to take
        let action = CompetitionStateMachine.checkHeartbeatAction(competition, currentTime);
        Debug.print("Action for competition #" # Nat.toText(competition.id) # ": " # debug_show (action));

        // Process based on the action
        switch (action) {
          case (#None) {
            // No action needed
          };

          case (#StartStaking) {
            Debug.print("Competition #" # Nat.toText(competition.id) # ": Starting staking round");

            // Get entry store for this competition
            switch (registryStore.getCompetitionEntryStoreById(competition.id)) {
              case (null) {
                Debug.print("Error: Cannot find competition #" # Nat.toText(competition.id));
              };
              case (?entryStore) {
                // Record price event if needed (only once per heartbeat)
                let priceEventId = getOrCreatePriceEvent(heartbeatId);
                Debug.print("Using price event #" # Nat.toText(priceEventId) # " for competition start");

                // Start staking round using the manager
                switch (competitionManager.startStakingRound(entryStore)) {
                  case (#err(error)) {
                    Debug.print("Error starting staking round: " # debug_show (error));
                  };
                  case (#ok(_)) {
                    Debug.print("Successfully started staking round");
                  };
                };
              };
            };
          };

          case (#EndStaking) {
            Debug.print("Competition #" # Nat.toText(competition.id) # ": Ending staking round");

            // Get entry store for this competition
            switch (registryStore.getCompetitionEntryStoreById(competition.id)) {
              case (null) {
                Debug.print("Error: Cannot find competition #" # Nat.toText(competition.id));
              };
              case (?entryStore) {
                // Log the current status before calling endStakingRound
                Debug.print("Competition #" # Nat.toText(competition.id) # " status before endStakingRound: " # debug_show (entryStore.getStatus()));

                // End staking round using the manager
                switch (competitionManager.endStakingRound(entryStore)) {
                  case (#err(error)) {
                    Debug.print("Error ending staking round: " # debug_show (error));
                  };
                  case (#ok(_)) {
                    Debug.print("Successfully ended staking round");

                    // Mark that we need to create a new competition
                    // (since this one is moving to Distribution)
                    shouldCreateNewCompetition := true;
                  };
                };
              };
            };
          };

          case (#DistributeReward) {
            // Calculate which distribution we're on
            let nextDistributionNumber = switch (competition.lastDistributionIndex) {
              case (null) { 0 }; // First distribution is 0
              case (?index) { index + 1 };
            };

            Debug.print(
              "Competition #" # Nat.toText(competition.id) #
              ": Distributing reward " # Nat.toText(nextDistributionNumber + 1) # // Display as 1-based for humans
              "/" # Nat.toText(competition.config.numberOfDistributionEvents),
            );

            // Record price event if needed (only once per heartbeat)
            let priceEventId = getOrCreatePriceEvent(heartbeatId);
            Debug.print("Using price event #" # Nat.toText(priceEventId) # " for distribution");

            // Create distribution event
            let distributionEvent : CompetitionEntryTypes.DistributionEvent = {
              distributionPrices = priceEventId;
              distributionNumber = nextDistributionNumber;
            };

            // Get entry store for this competition
            switch (registryStore.getCompetitionEntryStoreById(competition.id)) {
              case (null) {
                Debug.print("Error: Cannot find competition #" # Nat.toText(competition.id));
              };
              case (?entryStore) {
                // Process distribution using the manager FIRST (before updating lastDistributionIndex)
                switch (
                  competitionManager.processDistribution(
                    entryStore,
                    nextDistributionNumber,
                    distributionEvent,
                  )
                ) {
                  case (#err(error)) {
                    Debug.print("Error processing distribution: " # debug_show (error));
                  };
                  case (#ok(_)) {
                    Debug.print("Successfully processed distribution");
                    // Only add the distribution event AFTER successful processing
                    // This updates lastDistributionIndex after the manager has validated
                    entryStore.addDistributionEvent(distributionEvent);
                  };
                };
              };
            };
          };

          case (#EndCompetition) {
            Debug.print("Competition #" # Nat.toText(competition.id) # ": Ending competition");

            // Get entry store for this competition
            switch (registryStore.getCompetitionEntryStoreById(competition.id)) {
              case (null) {
                Debug.print("Error: Cannot find competition #" # Nat.toText(competition.id));
              };
              case (?entryStore) {
                // End competition using the manager
                switch (competitionManager.endCompetition(entryStore)) {
                  case (#err(error)) {
                    Debug.print("Error ending competition: " # debug_show (error));
                  };
                  case (#ok(_)) {
                    Debug.print("Successfully ended competition");
                  };
                };
              };
            };
          };
        };
      };

      // 3. Create new competition if needed
      if (shouldCreateNewCompetition or CompetitionStateMachine.shouldCreateNewCompetition(allCompetitions, currentTime)) {
        Debug.print("Creating new competition to maintain continuous operation");

        switch (registryStore.createCompetition()) {
          case (#err(error)) {
            Debug.print("Error creating new competition: " # debug_show (error));
          };
          case (#ok(newId)) {
            Debug.print("Created new competition #" # Nat.toText(newId));

            // The new competition starts in PreAnnouncement, so no immediate action needed
          };
        };
      };
    };

    /**
     * Get or create a price event for the current heartbeat.
     * Ensures we only create one price event per heartbeat.
     */
    private func getOrCreatePriceEvent(heartbeatId : Nat) : Nat {
      switch (currentHeartbeatPriceEvent) {
        case (?eventId) {
          // Already created a price event for this heartbeat
          eventId;
        };
        case (null) {
          // Check if we already have a price event for this heartbeat
          switch (eventManager.hasPriceEventForHeartbeat(heartbeatId)) {
            case (?existingId) {
              currentHeartbeatPriceEvent := ?existingId;
              existingId;
            };
            case (null) {
              // Need to create a new price event
              let priceEventId = eventManager.recordCurrentPrices();

              // Cache for reuse within this heartbeat
              currentHeartbeatPriceEvent := ?priceEventId;
              priceEventId;
            };
          };
        };
      };
    };
  };
};
