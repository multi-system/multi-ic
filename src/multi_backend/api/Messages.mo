import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {
  public type TokenRequest = {
    canisterId : Principal;
  };

  // Request types (with descriptive names ending in "Request")
  public type ApproveTokenRequest = {
    canisterId : Principal;
  };

  public type InitializeRequest = {
    supplyUnit : Nat;
    multiToken : TokenRequest;
    governanceToken : TokenRequest;
    backingTokens : [{
      canisterId : Principal;
      backingUnit : Nat;
    }];
  };

  public type DepositRequest = {
    token : Principal;
    amount : Nat;
  };

  public type WithdrawRequest = {
    token : Principal;
    amount : Nat;
  };

  public type IssueRequest = {
    amount : Nat;
  };

  public type RedeemRequest = {
    amount : Nat;
  };

  // Standard error types
  public type CommonError = {
    #NotInitialized;
    #AlreadyInitialized;
    #Unauthorized;
    #InsufficientBalance : {
      token : Principal;
      required : Nat;
      balance : Nat;
    };
    #InvalidAmount : {
      reason : Text;
      amount : Nat;
    };
    #TokenError : {
      token : Principal;
      code : Nat;
      message : Text;
    };
    #TokenAlreadyApproved : Principal;
    #TokenNotApproved : Principal;
    #LedgerError : Text;
    #InvalidSupplyUnit;
    #InvalidSupplyChange : {
      currentSupply : Nat;
      requestedChange : Nat;
      reason : Text;
    };
    #Other : { code : Nat; message : Text };
  };

  // Response types using standardized Result pattern
  public type ApproveTokenResponse = Result.Result<(), CommonError>;
  public type InitializeResponse = Result.Result<(), CommonError>;
  public type DepositResponse = Result.Result<(), CommonError>;
  public type WithdrawResponse = Result.Result<(), CommonError>;
  public type IssueResponse = Result.Result<(), CommonError>;
  public type RedeemResponse = Result.Result<(), CommonError>;

  // Success response types
  public type BackingTokenInfo = {
    tokenInfo : TokenRequest;
    backingUnit : Nat;
    reserveQuantity : Nat;
  };

  public type UserBalanceInfo = {
    user : Principal;
    token : Principal;
    balance : Nat;
  };

  public type SystemInfo = {
    initialized : Bool;
    totalSupply : Nat;
    supplyUnit : Nat;
    multiToken : TokenRequest;
    governanceToken : TokenRequest;
    backingTokens : [BackingTokenInfo];
  };

  // Query results
  public type GetTokensResponse = Result.Result<[BackingTokenInfo], CommonError>;
  public type GetBalanceResponse = Result.Result<Nat, CommonError>;
  public type GetUserBalancesResponse = Result.Result<[UserBalanceInfo], CommonError>;
  public type GetSystemInfoResponse = Result.Result<SystemInfo, CommonError>;
};
