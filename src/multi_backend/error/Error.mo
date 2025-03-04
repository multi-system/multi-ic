import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Types "../types/Types";

module {
  // Common error structures
  public type InsufficientBalanceError = {
    token : Types.Token;
    required : Nat;
    balance : Nat;
  };

  // Error type for initialization-related operations
  public type InitError = {
    #AlreadyInitialized;
    #InvalidSupplyUnit;
    #Unauthorized;
    #DuplicateToken : Types.Token;
    #InvalidBackingUnit : Types.Token;
    #TokenNotApproved : Types.Token;
    #InvalidPrincipal : { principal : Principal; reason : Text };
  };

  public func initErrorMessage(error : InitError) : Text {
    switch (error) {
      case (#AlreadyInitialized) "System has already been initialized";
      case (#InvalidSupplyUnit) "Supply unit must be greater than zero";
      case (#Unauthorized) "Caller is not authorized to perform this action";
      case (#DuplicateToken(token)) "Duplicate token " # Principal.toText(token) # " in initialization config";
      case (#InvalidBackingUnit(token)) "Backing unit for token " # Principal.toText(token) # " must be greater than zero";
      case (#TokenNotApproved(token)) "Token " # Principal.toText(token) # " has not been approved";
      case (#InvalidPrincipal({ principal; reason })) "Invalid principal " # Principal.toText(principal) # ": " # reason;
    };
  };

  // Error type for standard operations (issue, redeem, etc.)
  public type OperationError = {
    #NotInitialized;
    #InsufficientBalance : InsufficientBalanceError;
    #InvalidAmount : {
      reason : Text;
      amount : Nat;
    };
    #BackingUnitBecameZero : {
      token : Types.Token;
      reserveQuantity : Nat;
      eta : Nat;
    };
    #InvalidSupplyChange : {
      currentSupply : Nat;
      requestedChange : Nat;
      reason : Text;
    };
    #TokenNotApproved : Types.Token;
    #InvalidPrincipal : { principal : Principal; reason : Text };
  };

  public func operationErrorMessage(error : OperationError) : Text {
    switch (error) {
      case (#NotInitialized) "System must be initialized before performing operations";
      case (#InsufficientBalance({ token; required; balance })) "Insufficient balance for token " # Principal.toText(token) #
      ": required " # Int.toText(required) #
      " but only have " # Int.toText(balance);
      case (#InvalidAmount({ reason; amount })) "Invalid amount " # Int.toText(amount) # ": " # reason;
      case (#BackingUnitBecameZero({ token; reserveQuantity; eta })) "Backing unit would become zero for token " # Principal.toText(token) #
      ": reserve quantity " # Int.toText(reserveQuantity) #
      " with new eta " # Int.toText(eta);
      case (#InvalidSupplyChange({ currentSupply; requestedChange; reason })) "Invalid supply change: current supply " # Int.toText(currentSupply) #
      ", requested change " # Int.toText(requestedChange) #
      " - " # reason;
      case (#TokenNotApproved(token)) "Token " # Principal.toText(token) # " has not been approved";
      case (#InvalidPrincipal({ principal; reason })) "Invalid principal " # Principal.toText(principal) # ": " # reason;
    };
  };

  // Error type specific to token approval process
  public type ApprovalError = {
    #AlreadyInitialized;
    #TokenAlreadyApproved : Types.Token;
    #Unauthorized;
    #LedgerError : Text;
    #TokenNotApproved : Types.Token;
    #InvalidPrincipal : { principal : Principal; reason : Text };
  };

  public func approvalErrorMessage(error : ApprovalError) : Text {
    switch (error) {
      case (#AlreadyInitialized) "Cannot approve tokens after system initialization";
      case (#TokenAlreadyApproved(token)) "Token " # Principal.toText(token) # " is already approved";
      case (#Unauthorized) "Only the owner can approve tokens";
      case (#LedgerError(msg)) "Ledger operation failed: " # msg;
      case (#TokenNotApproved(token)) "Token " # Principal.toText(token) # " has not been approved";
      case (#InvalidPrincipal({ principal; reason })) "Invalid token principal " # Principal.toText(principal) # ": " # reason;
    };
  };

  // Error type for virtual account operations
  public type TransferError = {
    #InsufficientBalance : InsufficientBalanceError;
    #TokenNotSupported : Types.Token;
    #TransferFailed : {
      token : Types.Token;
      error : Text;
    };
    #InvalidPrincipal : { principal : Principal; reason : Text };
  };

  public func transferErrorMessage(error : TransferError) : Text {
    switch (error) {
      case (#InsufficientBalance({ token; required; balance })) "Insufficient balance for token " # Principal.toText(token) #
      ": required " # Int.toText(required) #
      " but only have " # Int.toText(balance);
      case (#TokenNotSupported(token)) "Token " # Principal.toText(token) # " is not supported";
      case (#TransferFailed({ token; error })) "Transfer failed for token " # Principal.toText(token) # ": " # error;
      case (#InvalidPrincipal({ principal; reason })) "Invalid principal " # Principal.toText(principal) # ": " # reason;
    };
  };

  // Error type for competition-related operations
  public type CompetitionError = {
    #InsufficientStake : {
      token : Types.Token;
      required : Nat;
      available : Nat;
    };
    #TokenNotApproved : Types.Token;
    #InvalidSubmission : { reason : Text };
    #VolumeLimitExceeded : {
      limit : Nat;
      requested : Nat;
    };
    #CompetitionNotActive;
    #InvalidPhase : { current : Text; required : Text };
    #Unauthorized;
    #OperationFailed : Text;
  };

  public func competitionErrorMessage(error : CompetitionError) : Text {
    switch (error) {
      case (#InsufficientStake({ token; required; available })) "Insufficient stake for token " # Principal.toText(token) # ": required " #
      Int.toText(required) # " but only have " # Int.toText(available);
      case (#TokenNotApproved(token)) "Token " # Principal.toText(token) # " is not approved for this competition";
      case (#InvalidSubmission({ reason })) "Invalid submission: " # reason;
      case (#VolumeLimitExceeded({ limit; requested })) "Volume limit exceeded: limit " # Int.toText(limit) # ", requested " # Int.toText(requested);
      case (#CompetitionNotActive) "Competition is not currently active";
      case (#InvalidPhase({ current; required })) "Invalid competition phase: current phase is " # current # ", required phase is " # required;
      case (#Unauthorized) "Caller is not authorized to perform this action";
      case (#OperationFailed(msg)) "Operation failed: " # msg;
    };
  };

  // General error type that can be any of the above
  public type ErrorType = {
    #Init : InitError;
    #Operation : OperationError;
    #Approval : ApprovalError;
    #Transfer : TransferError;
    #Competition : CompetitionError;
  };
};
