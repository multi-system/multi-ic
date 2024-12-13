import Principal "mo:base/Principal";

module {
  public type TokenConfig = {
    canisterId : Principal;
    backingUnit : Nat;
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
};
