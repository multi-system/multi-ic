import Time "mo:base/Time";
import Types "Types";
import SystemStakeTypes "SystemStakeTypes";
import SubmissionTypes "SubmissionTypes";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../types/AccountTypes";

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

  // Configuration parameters for a specific competition instance
  public type CompetitionConfig = {
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

  // A complete record of a single competition
  public type CompetitionEntry = {
    id : Nat; // Unique competition identifier
    startTime : Time.Time; // When competition started
    endTime : ?Time.Time; // When competition ended (if completed)
    status : CompetitionStatus; // Current status

    // Configuration when competition started
    config : CompetitionConfig; // Configuration for this competition

    // All submissions for this competition
    submissions : [SubmissionTypes.Submission]; // The actual submissions, not just IDs
    nextSubmissionId : Nat; // Counter for generating submission IDs in this competition

    // Stake accounts for this competition only
    // Maps user accounts to token balances for staked tokens
    stakeAccounts : StableHashMap.StableHashMap<Types.Account, AccountTypes.BalanceMap>;

    // Stake totals
    totalGovStake : Nat; // Total governance tokens staked
    totalMultiStake : Nat; // Total multi tokens staked

    // Rate adjustments & limits
    adjustedGovRate : ?Types.Ratio; // Adjusted stake rate after competition filled
    adjustedMultiRate : ?Types.Ratio; // Adjusted stake rate after competition filled
    volumeLimit : Nat; // Calculated volume limit for this competition

    // System participation
    systemStake : ?SystemStakeTypes.SystemStake; // System's stake participation
  };
};
