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

  public type IssueArgs = {
    amount : Nat;
  };

  public type IssueResponse = {
    #Success;
    #NotInitialized;
    #InvalidAmount : Text;
    #InsufficientAllowance : Principal;
    #TransferFailed : {
      token : Principal;
      error : Text;
    };
  };
};
