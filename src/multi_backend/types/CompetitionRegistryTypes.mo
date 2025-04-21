import Time "mo:base/Time";
import Types "Types";
import CompetitionEntryTypes "CompetitionEntryTypes";

module {
  // Global configuration for the competition system
  public type GlobalCompetitionConfig = {
    govToken : Types.Token; // Governance token identifier
    multiToken : Types.Token; // Multi token identifier
    approvedTokens : [Types.Token]; // Tokens approved for submission
    competitionPrices : [Types.Price]; // Prices for approved tokens
    theta : Types.Ratio; // Volume limit ratio
    govRate : Types.Ratio; // Base stake rate for governance tokens
    multiRate : Types.Ratio; // Base stake rate for multi tokens
    systemStakeGov : Types.Ratio; // System stake multiplier for gov tokens
    systemStakeMulti : Types.Ratio; // System stake multiplier for multi tokens
    competitionCycleDuration : Time.Time; // Total time until next competition starts
    preAnnouncementPeriod : Time.Time; // Duration of initial buffer period
    rewardDistributionFrequency : Time.Time; // Time between reward distributions
    numberOfDistributionEvents : Nat; // Number of distribution events
  };

  // Registry that manages all competitions
  public type RegistryState = {
    var hasInitialized : Bool; // Whether the system is initialized
    var globalConfig : GlobalCompetitionConfig; // Current global configuration
    var competitions : [CompetitionEntryTypes.CompetitionEntry]; // All competitions
    var currentCompetitionId : ?Nat; // ID of currently active competition (if any)
    var nextCompetitionId : Nat; // Counter for generating competition IDs
    var epochStartTime : Time.Time; // Fixed reference time when competition cycles begin
  };
};
