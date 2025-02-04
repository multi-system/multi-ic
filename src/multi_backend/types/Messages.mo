import Principal "mo:base/Principal";

module {
  public type TokenConfig = {
    canisterId : Principal;
    backingUnit : Nat;
  };

  public type BackingTokenResponse = {
    tokenInfo : { canisterId : Principal };
    backingUnit : Nat;
    reserveQuantity : Nat;
  };

  public type InitializeMsg = {
    supplyUnit : Nat;
    backingTokens : [TokenConfig];
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

  public type OperationResponse = {
    #Success;
    #NotInitialized;
    #InvalidAmount : Text;
    #InsufficientBalance;
    #TransferFailed : {
      token : Principal;
      error : Text;
    };
  };

  public type IssueResponse = {
    #Success;
    #NotInitialized;
    #InvalidAmount : Text;
  };

  public type RedeemResponse = {
    #Success;
    #NotInitialized;
    #InvalidAmount : Text;
  };
};
