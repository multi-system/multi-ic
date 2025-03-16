import Time "mo:base/Time";
import Types "Types";
import SystemStakeTypes "SystemStakeTypes";
import SubmissionTypes "SubmissionTypes";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

module {
  // Configuration parameters for a competition
  public type CompetitionConfig = {
    govToken : Types.Token; // Governance token identifier
    multiToken : Types.Token; // Multi token identifier
    approvedTokens : [Types.Token]; // Tokens approved for submission
    competitionPrices : [Types.Price]; // Prices for approved tokens
    theta : Types.Ratio; // Volume limit ratio
    govRate : Types.Ratio; // Stake rate for governance tokens
    multiRate : Types.Ratio; // Stake rate for multi tokens
    systemStakeGov : Types.Ratio; // System stake multiplier for gov tokens
    systemStakeMulti : Types.Ratio; // System stake multiplier for multi tokens
    competitionPeriodLength : Time.Time; // Duration of active competition
    competitionSpacing : Time.Time; // Time between competitions
    settlementDuration : Time.Time; // Duration for settlement
    rewardDistributionFrequency : Time.Time; // Time between reward distributions
    numberOfDistributionEvents : Nat; // Number of distribution events
  };

  // Current status of a competition
  public type CompetitionStatus = {
    #NotStarted; // Competition not yet begun
    #Active; // Competition accepting submissions
    #Adjusting; // Competition being finalized with rate adjustments
    #Settling; // Competition in settlement phase
    #Completed; // Competition completed
  };

  // Competition record
  public type Competition = {
    id : Nat; // Unique competition identifier
    config : CompetitionConfig; // Competition configuration
    startTime : Time.Time; // When competition started
    endTime : ?Time.Time; // When competition ended (if completed)
    status : CompetitionStatus; // Current status
    systemStake : ?SystemStakeTypes.SystemStake; // System participation
  };

  // Competition state stored in the canister
  public type CompetitionState = {
    var hasInitialized : Bool;
    var competitionActive : Bool;
    var config : CompetitionConfig;
    var submissions : [SubmissionTypes.Submission];
    var nextSubmissionId : Nat;
    var totalGovStake : Nat;
    var totalMultiStake : Nat;
  };
};
