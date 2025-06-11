import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

import CompetitionEntryTypes "../types/CompetitionEntryTypes";

/**
 * Pure state machine logic for competition actions.
 * No side effects - only calculates what action should be taken.
 */
module {
  // Actions that can be triggered by the heartbeat
  public type HeartbeatAction = {
    #None; // No action needed
    #StartStaking; // Start accepting stakes (PreAnnouncement --> AcceptingStakes)
    #EndStaking; // End staking period (AcceptingStakes --> Distribution)
    #DistributeReward; // Distribute a reward
    #EndCompetition; // End the competition (Distribution --> Completed)
  };

  /**
   * Determine which action to take for a competition based on the current time.
   * This is a pure function with no side effects.
   *
   * @param competition The competition to check
   * @param currentTime Current timestamp
   * @return Which action to take (if any)
   */
  public func checkHeartbeatAction(
    competition : CompetitionEntryTypes.Competition,
    currentTime : Time.Time,
  ) : HeartbeatAction {
    let status = competition.status;
    let config = competition.config;
    let startTime = competition.startTime;

    // Calculate key time points
    let stakingStartTime = startTime + config.preAnnouncementDuration;
    let stakingEndTime = startTime + config.competitionCycleDuration;

    switch (status) {
      case (#PreAnnouncement) {
        // Check if pre-announcement period is over
        if (currentTime >= stakingStartTime) {
          return #StartStaking;
        };
      };

      case (#AcceptingStakes) {
        // Check if competition cycle is complete
        if (currentTime >= stakingEndTime) {
          return #EndStaking;
        };
      };

      case (#Distribution) {
        // Calculate time since distribution started
        let timeSinceDistributionStart = currentTime - stakingEndTime;

        // Calculate which distribution event we should be on
        let currentDistributionIndex = Int.abs(timeSinceDistributionStart / config.rewardDistributionDuration);

        // Get the last completed distribution
        let lastIndex = switch (competition.lastDistributionIndex) {
          case (null) { -1 }; // No distributions yet
          case (?index) { index };
        };

        // First check if we need to execute the next distribution
        if (currentDistributionIndex > lastIndex) {
          // But only if we haven't done all distributions yet
          if (lastIndex + 1 < config.numberOfDistributionEvents) {
            return #DistributeReward;
          };
        };

        // Only check for competition end after verifying all distributions are actually complete
        if (lastIndex + 1 >= config.numberOfDistributionEvents) {
          return #EndCompetition;
        };
      };

      case (#Finalizing or #Settlement) {
        // These are transitional states handled within EndStaking
        // No time-based actions needed
      };

      case (#Completed) {
        // Competition is done, no actions needed
      };
    };

    // Default: no action needed
    #None;
  };

  /**
   * Check if a competition is "active" (can accept stakes).
   * Only competitions in PreAnnouncement or AcceptingStakes are considered active.
   */
  public func isCompetitionActive(competition : CompetitionEntryTypes.Competition) : Bool {
    switch (competition.status) {
      case (#PreAnnouncement or #AcceptingStakes) { true };
      case (_) { false };
    };
  };

  /**
   * Check if it's time to create a new competition.
   * A new competition should be created when the current one transitions to Distribution.
   */
  public func shouldCreateNewCompetition(
    competitions : [CompetitionEntryTypes.Competition],
    currentTime : Time.Time,
  ) : Bool {
    // Check if any competition is currently active
    for (competition in competitions.vals()) {
      if (isCompetitionActive(competition)) {
        return false; // Already have an active competition
      };
    };

    // No active competition - we should create one
    return true;
  };

  /**
   * Calculate when the next competition should start based on the current competition.
   * This ensures no gaps between competitions.
   */
  public func calculateNextCompetitionStartTime(
    currentCompetition : CompetitionEntryTypes.Competition
  ) : Time.Time {
    // Next competition starts exactly when current competition's cycle ends
    currentCompetition.startTime + currentCompetition.config.competitionCycleDuration;
  };

  /**
   * Get the distribution event number for a competition at a given time.
   * Returns null if not in distribution phase or if time is before first distribution.
   */
  public func getDistributionEventNumber(
    competition : CompetitionEntryTypes.Competition,
    currentTime : Time.Time,
  ) : ?Nat {
    switch (competition.status) {
      case (#Distribution) {
        let stakingEndTime = competition.startTime + competition.config.competitionCycleDuration;
        let timeSinceDistributionStart = currentTime - stakingEndTime;

        if (timeSinceDistributionStart >= 0) {
          let eventNumber = Int.abs(timeSinceDistributionStart / competition.config.rewardDistributionDuration);
          if (eventNumber < competition.config.numberOfDistributionEvents) {
            return ?eventNumber;
          };
        };
        null;
      };
      case (_) { null };
    };
  };

  /**
   * Check if a price event is needed for the given action.
   * Price events are only needed for:
   * - StartStaking (transition to AcceptingStakes)
   * - DistributeReward (distribution events)
   */
  public func needsPriceEvent(action : HeartbeatAction) : Bool {
    switch (action) {
      case (#StartStaking or #DistributeReward) { true };
      case (_) { false };
    };
  };
};
