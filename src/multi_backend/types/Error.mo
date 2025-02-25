import Principal "mo:base/Principal";
import Int "mo:base/Int";

module {
  // Error type for initialization-related operations
  public type InitError = {
    #AlreadyInitialized;
    #InsufficientBalance : {
      token : Principal;
      required : Nat;
      balance : Nat;
    };
    #InvalidSupplyUnit;
    #TokenNotApproved : Principal;
    #Unauthorized;
  };

  public func initErrorMessage(error : InitError) : Text {
    switch (error) {
      case (#AlreadyInitialized) "System has already been initialized";
      case (#InsufficientBalance({ token; required; balance })) "Insufficient balance for token " # Principal.toText(token) #
      ": required " # Int.toText(required) #
      " but only have " # Int.toText(balance);
      case (#InvalidSupplyUnit) "Supply unit must be greater than zero and divide total supply evenly";
      case (#TokenNotApproved(token)) "Token " # Principal.toText(token) # " has not been approved";
      case (#Unauthorized) "Caller is not authorized to perform this action";
    };
  };

  // Error type for standard operations (issue, redeem, etc.)
  public type OperationError = {
    #NotInitialized;
    #InsufficientBalance : {
      token : Principal;
      required : Nat;
      balance : Nat;
    };
    #InvalidAmount : {
      reason : Text;
      amount : Nat;
    };
    #BackingUnitBecameZero : {
      token : Principal;
      reserveQuantity : Nat;
      eta : Nat;
    };
    #InvalidSupplyChange : {
      currentSupply : Nat;
      requestedChange : Nat;
      reason : Text;
    };
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
    };
  };

  // Error type specific to token approval process
  public type ApprovalError = {
    #AlreadyInitialized;
    #TokenAlreadyApproved : Principal;
    #Unauthorized;
    #LedgerError : Text;
  };

  public func approvalErrorMessage(error : ApprovalError) : Text {
    switch (error) {
      case (#AlreadyInitialized) "Cannot approve tokens after system initialization";
      case (#TokenAlreadyApproved(token)) "Token " # Principal.toText(token) # " is already approved";
      case (#Unauthorized) "Only the owner can approve tokens";
      case (#LedgerError(msg)) "Ledger operation failed: " # msg;
    };
  };

  // Error type for virtual account operations
  public type TransferError = {
    #InsufficientBalance : {
      token : Principal;
      required : Nat;
      balance : Nat;
    };
    #TokenNotSupported : Principal;
    #TransferFailed : {
      token : Principal;
      error : Text;
    };
  };

  public func transferErrorMessage(error : TransferError) : Text {
    switch (error) {
      case (#InsufficientBalance({ token; required; balance })) "Insufficient balance for token " # Principal.toText(token) #
      ": required " # Int.toText(required) #
      " but only have " # Int.toText(balance);
      case (#TokenNotSupported(token)) "Token " # Principal.toText(token) # " is not supported";
      case (#TransferFailed({ token; error })) "Transfer failed for token " # Principal.toText(token) # ": " # error;
    };
  };
};
