import Types "Types";
import SubmissionTypes "SubmissionTypes";

module {
  // Record of a payout received in a single distribution event
  public type DistributionPayout = {
    distributionNumber : Nat; // Which distribution event (0 to l-1)
    payouts : [(Types.Token, Nat)]; // Payouts per stake token type
  };

  // Unified position type for both user and system positions
  public type Position = {
    quantity : Types.Amount; // Amount of the token held
    stakes : [(Types.Token, Types.Amount)]; // Stakes per token type
    submissionId : ?SubmissionTypes.SubmissionId; // Reference to originating submission (null for system positions)
    isSystem : Bool; // Flag indicating if this is a system position

    // Distribution payout history
    distributionPayouts : [DistributionPayout]; // Track all payouts received by this position
  };
};
