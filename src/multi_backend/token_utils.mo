import ICRC2 "mo:icrc2-types";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";

module {
  public type Account = ICRC2.Account;
  public type Allowance = ICRC2.Allowance;
  public type ApproveArgs = ICRC2.ApproveArgs;
  public type AllowanceArgs = ICRC2.AllowanceArgs;

  public let DEFAULT_FEE : Nat = 10_000;

  /// Generates a unique key for allowance storage
  public func getAllowanceKey(owner : Principal, spender : Principal) : Text {
    Principal.toText(owner) # ":" # Principal.toText(spender);
  };

  /// Validates approval parameters according to ICRC2 standard
  public func validateApproval(
    args : ApproveArgs,
    current_time : Nat64,
    existing_allowance : ?Allowance,
  ) : Result.Result<(), Text> {
    // Amount validation (required)
    if (args.amount == 0) {
      return #err("Amount must be greater than 0");
    };

    // Expires_at validation (if provided)
    switch (args.expires_at) {
      case (?expires) {
        if (expires <= current_time) {
          return #err("Expiry time must be in the future");
        };
      };
      case null {};
    };

    // Expected allowance validation (if provided)
    switch (args.expected_allowance, existing_allowance) {
      case (?expected, ?current) {
        if (current.allowance != expected) {
          return #err("Existing allowance does not match expected value");
        };
      };
      case (?expected, null) {
        if (expected != 0) {
          return #err("No existing allowance");
        };
      };
      case (null, _) {};
    };

    #ok(());
  };
};
