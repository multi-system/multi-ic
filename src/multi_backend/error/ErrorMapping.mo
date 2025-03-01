import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Error "./Error";
import Messages "../api/Messages";

module {
  // Common error code constants
  // Core System errors
  private let _ERROR_ALREADY_INITIALIZED : Nat = 2001;
  private let _ERROR_NOT_INITIALIZED : Nat = 2002;
  private let _ERROR_INVALID_SUPPLY_UNIT : Nat = 2101;
  private let ERROR_INVALID_BACKING_UNIT : Nat = 2102;
  private let ERROR_DUPLICATE_TOKEN : Nat = 2103;
  private let ERROR_INVALID_PRINCIPAL : Nat = 2104;

  // Token Registry errors
  private let _ERROR_TOKEN_NOT_APPROVED : Nat = 1101;
  private let _ERROR_TOKEN_ALREADY_APPROVED : Nat = 1102;

  // Authorization
  private let _ERROR_UNAUTHORIZED : Nat = 9001;

  // BackingApi Operation errors
  private let _ERROR_INSUFFICIENT_BALANCE : Nat = 3101;
  private let _ERROR_INVALID_AMOUNT : Nat = 3102;
  private let ERROR_BACKING_UNIT_ZERO : Nat = 3103;
  private let _ERROR_INVALID_SUPPLY_CHANGE : Nat = 3201;

  // External Ledger errors
  private let _ERROR_LEDGER_ERROR : Nat = 5001;
  private let _ERROR_LEDGER_COMMUNICATION : Nat = 5002;
  private let _ERROR_LEDGER_TRANSFER : Nat = 5101;
  private let _ERROR_LEDGER_ALLOWANCE : Nat = 5102;

  // Virtual Account errors
  private let ERROR_TRANSFER_FAILED : Nat = 4101;
  private let ERROR_TOKEN_NOT_SUPPORTED : Nat = 4001;

  // Catch-all
  private let ERROR_UNEXPECTED : Nat = 9999;

  // Map internal Error.InitError to Messages.CommonError
  public func mapInitError(error : Error.InitError) : Messages.CommonError {
    switch (error) {
      case (#AlreadyInitialized) { #AlreadyInitialized };
      case (#InvalidSupplyUnit) { #InvalidSupplyUnit };
      case (#TokenNotApproved(token)) { #TokenNotApproved(token) };
      case (#Unauthorized) { #Unauthorized };
      case (#DuplicateToken(token)) {
        #TokenError({
          token = token;
          code = ERROR_DUPLICATE_TOKEN;
          message = "Duplicate token in initialization config";
        });
      };
      case (#InvalidBackingUnit(token)) {
        #TokenError({
          token = token;
          code = ERROR_INVALID_BACKING_UNIT;
          message = "Invalid backing unit for token";
        });
      };
      case (#InvalidPrincipal({ principal; reason })) {
        #TokenError({
          token = principal;
          code = ERROR_INVALID_PRINCIPAL;
          message = reason;
        });
      };
      case (_) {
        #Other({
          code = ERROR_UNEXPECTED;
          message = "Unhandled initialization error";
        });
      };
    };
  };

  // Map internal Error.OperationError to Messages.CommonError
  public func mapOperationError(error : Error.OperationError) : Messages.CommonError {
    switch (error) {
      case (#NotInitialized) { #NotInitialized };
      case (#InsufficientBalance({ token; required; balance })) {
        #InsufficientBalance({
          token = token;
          required = required;
          balance = balance;
        });
      };
      case (#InvalidAmount({ reason; amount })) {
        #InvalidAmount({ reason = reason; amount = amount });
      };
      case (#BackingUnitBecameZero({ token; reserveQuantity; eta })) {
        #TokenError({
          token = token;
          code = ERROR_BACKING_UNIT_ZERO;
          message = "Backing unit would become zero: reserve quantity " #
          Nat.toText(reserveQuantity) # " with eta " # Nat.toText(eta);
        });
      };
      case (#InvalidSupplyChange({ currentSupply; requestedChange; reason })) {
        #InvalidSupplyChange({
          currentSupply = currentSupply;
          requestedChange = requestedChange;
          reason = reason;
        });
      };
      case (#TokenNotApproved(token)) { #TokenNotApproved(token) };
      case (#InvalidPrincipal({ principal; reason })) {
        #TokenError({
          token = principal;
          code = ERROR_INVALID_PRINCIPAL;
          message = reason;
        });
      };
      case (_) {
        #Other({
          code = ERROR_UNEXPECTED;
          message = "Unhandled operation error";
        });
      };
    };
  };

  // Map internal Error.ApprovalError to Messages.CommonError
  public func mapApprovalError(error : Error.ApprovalError) : Messages.CommonError {
    switch (error) {
      case (#AlreadyInitialized) { #AlreadyInitialized };
      case (#TokenAlreadyApproved(token)) { #TokenAlreadyApproved(token) };
      case (#Unauthorized) { #Unauthorized };
      case (#LedgerError(msg)) { #LedgerError(msg) };
      case (#TokenNotApproved(token)) { #TokenNotApproved(token) };
      case (#InvalidPrincipal({ principal; reason })) {
        #TokenError({
          token = principal;
          code = ERROR_INVALID_PRINCIPAL;
          message = reason;
        });
      };
      case (_) {
        #Other({
          code = ERROR_UNEXPECTED;
          message = "Unhandled approval error";
        });
      };
    };
  };

  // Simple mapper for a direct Result<(), ApprovalError> to ApproveTokenResponse
  public func mapDirectApprovalResult(result : Result.Result<(), Error.ApprovalError>) : Messages.ApproveTokenResponse {
    switch (result) {
      case (#err(e)) { #err(mapApprovalError(e)) };
      case (#ok()) { #ok(()) };
    };
  };

  // Map internal Error.TransferError to Messages.CommonError
  public func mapTransferError(error : Error.TransferError) : Messages.CommonError {
    switch (error) {
      case (#InsufficientBalance({ token; required; balance })) {
        #InsufficientBalance({
          token = token;
          required = required;
          balance = balance;
        });
      };
      case (#TokenNotSupported(token)) {
        #TokenError({
          token = token;
          code = ERROR_TOKEN_NOT_SUPPORTED;
          message = "Token not supported for transfer";
        });
      };
      case (#TransferFailed({ token; error })) {
        #TokenError({
          token = token;
          code = ERROR_TRANSFER_FAILED;
          message = error;
        });
      };
      case (#InvalidPrincipal({ principal; reason })) {
        #TokenError({
          token = principal;
          code = ERROR_INVALID_PRINCIPAL;
          message = reason;
        });
      };
      case (_) {
        #Other({
          code = ERROR_UNEXPECTED;
          message = "Unhandled transfer error";
        });
      };
    };
  };

  // Handle nested Results for approval operations
  public func mapApprovalResult<T>(result : Result.Result<Result.Result<T, Text>, Error.ApprovalError>) : Messages.ApproveTokenResponse {
    switch (result) {
      case (#err(e)) { #err(mapApprovalError(e)) };
      case (#ok(#err(e))) { #err(#LedgerError(e)) };
      case (#ok(#ok(_))) { #ok(()) };
    };
  };

  // Utils to map operation errors to specific response types
  public func mapToIssueResponse(error : Error.OperationError) : Messages.IssueResponse {
    #err(mapOperationError(error));
  };

  public func mapToRedeemResponse(error : Error.OperationError) : Messages.RedeemResponse {
    #err(mapOperationError(error));
  };

  public func mapToInitializeResponse(error : Error.InitError) : Messages.InitializeResponse {
    #err(mapInitError(error));
  };

  // Direct mapping from TransferError to DepositResponse
  public func mapToDepositResponse(error : Error.TransferError) : Messages.DepositResponse {
    #err(mapTransferError(error));
  };

  // Direct mapping from TransferError to WithdrawResponse
  public func mapToWithdrawResponse(error : Error.TransferError) : Messages.WithdrawResponse {
    #err(mapTransferError(error));
  };
};
