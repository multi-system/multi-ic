import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Types "../types/Types";

module {
  public type SubmissionId = Nat;

  public type StakeSubmission = {
    id : SubmissionId;
    participant : Types.Account;
    proposedQuantity : Types.Amount;
    finalQuantity : ?Types.Amount;
    govStake : Types.Amount;
    multiStake : Types.Amount;
    timestamp : Time.Time;
  };

  public type SystemStake = {
    defensiveQuantity : Types.Amount;
    govStake : Types.Amount;
    multiStake : Types.Amount;
  };
};
