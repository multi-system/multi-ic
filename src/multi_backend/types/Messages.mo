import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Error "./Error";

module {
  // Request Messages
  public type ApproveTokenMsg = {
    canisterId : Principal;
  };

  public type InitializeMsg = {
    supplyUnit : Nat;
    totalSupply : Nat;
    initialAmounts : [(Principal, Nat)]; // (tokenId, amount) pairs for initial reserves
    multiToken : Principal; // Canister ID of the ICRC token canister
  };

  public type DepositArgs = {
    token : Principal;
    amount : Nat;
  };

  public type WithdrawArgs = {
    token : Principal;
    amount : Nat;
  };

  public type IssueArgs = {
    amount : Nat;
  };

  public type RedeemArgs = {
    amount : Nat;
  };

  // Query response types
  public type BackingTokenInfo = {
    tokenInfo : { canisterId : Principal };
    backingUnit : Nat; // Current backing unit for this token
    reserveQuantity : Nat; // Actual amount held in reserve
  };

  // Response type aliases using Result
  public type ApproveTokenResponse = Result.Result<(), Error.ApprovalError>;
  public type InitializeResponse = Result.Result<(), Error.InitError>;
  public type DepositResponse = Result.Result<(), Error.TransferError>;
  public type WithdrawResponse = Result.Result<(), Error.TransferError>;
  public type IssueResponse = Result.Result<(), Error.OperationError>;
  public type RedeemResponse = Result.Result<(), Error.OperationError>;

  // Query response type
  public type GetBackingTokensResponse = [BackingTokenInfo];
};
