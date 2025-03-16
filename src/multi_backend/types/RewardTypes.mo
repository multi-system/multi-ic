import Types "Types";
import SubmissionTypes "SubmissionTypes";

module {
  // Unified position type for both user and system positions
  public type Position = {
    quantity : Types.Amount; // Amount of the token held
    govStake : Types.Amount; // Associated governance token stake
    multiStake : Types.Amount; // Associated multi token stake
    submissionId : ?SubmissionTypes.SubmissionId; // Reference to originating submission (null for system positions)
    isSystem : Bool; // Flag indicating if this is a system position
  };
};
