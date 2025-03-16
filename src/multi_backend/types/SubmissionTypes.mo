// SubmissionTypes.mo
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Types "Types";

module {
  // Unique identifier for submissions
  public type SubmissionId = Nat;

  // Status of a submission - temporal approach
  public type SubmissionStatus = {
    #PreRound; // Before entering the round
    #ActiveRound; // Active in current round
    #PostRound; // Round has closed
    #PostSettlement; // After market settlement
    #Rejected; // Invalid submission
  };

  // Reason for rejection, if applicable
  public type RejectionReason = {
    #InsufficientBalance; // User doesn't have enough balance
    #InvalidToken; // Token not approved for competition
    #CompetitionNotActive; // Competition isn't active
    #Other : Text; // Other reasons
  };

  // A submission that records a user's participation
  public type Submission = {
    id : SubmissionId;
    participant : Types.Account;

    // Stake information
    govStake : Types.Amount; // Governance tokens staked
    multiStake : Types.Amount; // Multi tokens staked

    // Token information
    token : Types.Token; // Token the user wants to acquire

    // Initial submission
    proposedQuantity : Types.Amount; // Initial quantity proposed by user
    timestamp : Time.Time; // When the submission was created

    // Current state
    status : SubmissionStatus;
    rejectionReason : ?RejectionReason; // Reason for rejection, if status is #Rejected

    // Adjustment results after round closure
    adjustedQuantity : ?Types.Amount; // Quantity after rate adjustment in post-round

    // Settlement results
    soldQuantity : ?Types.Amount; // Amount actually sold during settlement
    executionPrice : ?Types.Price; // Price at which tokens were acquired

    // Position reference for rewards
    positionId : ?Nat;
  };

  // Reference to a submission in the queue
  public type QueuedSubmission = {
    submissionId : SubmissionId;
  };

  // Result returned after processing a submission
  public type SubmissionResult = {
    submissionId : SubmissionId;
  };
};
