import Principal "mo:base/Principal";

module {
  public type IssueArgs = {
    amount : Nat;
  };

  public type IssueResponse = {
    #Success;
    #NotInitialized;
    #InsufficientAllowance : Principal;
    #TransferFailed : {
      token : Principal;
      error : Text;
    };
    #InvalidAmount : Text;
    #BackingValidationFailed : Text;
  };

  public type RedeemArgs = {
    amount : Nat;
  };

  public type RedeemResponse = {
    #Success;
    #NotInitialized;
    #InsufficientBalance : Nat;
    #TransferFailed : {
      token : Principal;
      error : Text;
    };
    #InvalidAmount : Text;
  };
};
