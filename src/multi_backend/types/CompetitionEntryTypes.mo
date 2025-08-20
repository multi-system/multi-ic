import Time "mo:base/Time";
import Types "Types";
import SystemStakeTypes "SystemStakeTypes";
import SubmissionTypes "SubmissionTypes";
import StakeTokenTypes "StakeTokenTypes";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../types/AccountTypes";
import EventTypes "EventTypes";
import RewardTypes "RewardTypes";

module {
  // Status of a competition
  public type CompetitionStatus = {
    #PreAnnouncement; // Initial buffer period before accepting stakes
    #AcceptingStakes; // Actively accepting stake requests
    #Finalizing; // Processing final calculations
    #Settlement; // Settling positions and transactions
    #Distribution; // Long-term reward distribution phase
    #Completed; // Fully completed (after all rewards distributed)
  };

  // Distribution event within a competition
  public type DistributionEvent = {
    distributionPrices : Nat; // Reference to price event ID used for distribution calculations
    distributionNumber : Nat; // Sequential number within competition
  };

  // Configuration parameters set by governance
  public type CompetitionConfig = {
    multiToken : Types.Token; // Multi token identifier
    approvedTokens : [Types.Token]; // Tokens approved for submission
    theta : Types.Ratio; // Volume limit ratio
    stakeTokenConfigs : [StakeTokenTypes.StakeTokenConfig]; // Configuration for all stake tokens
    competitionCycleDuration : Time.Time; // Total time until next competition starts
    preAnnouncementDuration : Time.Time; // Duration of initial buffer period
    rewardDistributionDuration : Time.Time; // Time between reward distributions
    numberOfDistributionEvents : Nat; // Number of distribution events
  };

  // A complete record of a single competition
  public type Competition = {
    id : Nat; // Unique competition identifier
    startTime : Time.Time; // When competition started
    completionTime : ?Time.Time; // When competition ended (if completed)
    status : CompetitionStatus; // Current status

    // Configuration and competition terms
    config : CompetitionConfig; // Governance-defined configuration
    competitionPrices : Nat; // Reference to price event ID used for competition prices

    // All submissions for this competition
    submissions : [SubmissionTypes.Submission];
    submissionCounter : Nat; // Counter for generating submission IDs in this competition

    // Stake accounts for this competition only
    // Maps user accounts to token balances for staked tokens
    stakeAccounts : StableHashMap.StableHashMap<Types.Account, AccountTypes.BalanceMap>;

    // Stake totals - one entry per configured stake token
    totalStakes : [(Types.Token, Nat)]; // Total stakes per token type

    // Rate adjustments & limits
    adjustedRates : ?[(Types.Token, Types.Ratio)]; // Adjusted stake rates after competition filled
    volumeLimit : Nat; // Calculated volume limit for this competition

    // System participation
    systemStake : ?SystemStakeTypes.SystemStake; // System's stake participation

    // Distribution tracking
    lastDistributionIndex : ?Nat; // Index of the most recent distribution (null if none yet)
    nextDistributionTime : ?Time.Time; // When the next distribution is scheduled
    distributionHistory : [DistributionEvent]; // Record of all distributions

    // Settlement and position tracking
    positions : [RewardTypes.Position]; // All positions in this competition
  };
};
