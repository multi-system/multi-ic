import Time "mo:base/Time";
import Types "Types";
import CompetitionEntryTypes "CompetitionEntryTypes";
import EventTypes "EventTypes";
import StakeTokenTypes "StakeTokenTypes";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

module {
  // Event registry to track system-wide events
  public type EventRegistry = {
    var heartbeats : StableHashMap.StableHashMap<Nat, EventTypes.HeartbeatEvent>; // Map of heartbeat ID to event
    var priceEvents : StableHashMap.StableHashMap<Nat, EventTypes.PriceEvent>; // Map of price event ID to event
    var nextHeartbeatId : Nat; // Counter for generating unique heartbeat IDs
    var nextPriceEventId : Nat; // Counter for generating unique price event IDs
    var lastUpdateTime : Time.Time; // Timestamp of the most recent heartbeat
  };

  // Global configuration for the competition system
  // These parameters serve as the template for new competitions
  // and are inherited by each competition when it's created
  public type GlobalCompetitionConfig = {
    multiToken : Types.Token; // Multi token identifier
    approvedTokens : [Types.Token]; // Tokens approved for submission
    theta : Types.Ratio; // Volume limit ratio
    stakeTokenConfigs : [StakeTokenTypes.StakeTokenConfig]; // Configuration for all stake tokens
    competitionCycleDuration : Time.Time; // Total time until next competition starts
    preAnnouncementDuration : Time.Time; // Duration of initial buffer period
    rewardDistributionDuration : Time.Time; // Time between reward distributions
    numberOfDistributionEvents : Nat; // Number of distribution events
  };

  // Registry that manages all competitions and system-wide events
  public type CompetitionRegistryState = {
    var hasInitialized : Bool; // Whether the system has been initialized
    var globalConfig : GlobalCompetitionConfig; // Current global configuration parameters
    var competitions : [CompetitionEntryTypes.Competition]; // All competitions in the system
    var currentCompetitionId : Nat; // ID of the currently active competition
    var startTime : Time.Time; // Reference time when competition cycles begin
    var eventRegistry : EventRegistry; // System-wide event tracking registry
  };
};
