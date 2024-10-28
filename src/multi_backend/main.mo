import ICRC2 "mo:icrc2-types";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Result "mo:base/Result";
import TokenUtils "./token_utils";

actor {
  // Use types from TokenUtils
  type Account = TokenUtils.Account;
  type Allowance = TokenUtils.Allowance;
  type ApproveArgs = TokenUtils.ApproveArgs;
  type AllowanceArgs = TokenUtils.AllowanceArgs;

  // State
  private let name_ : Text = "Multi Token";
  private let symbol_ : Text = "MULTI";
  private let decimals_ : Nat8 = 8;
  private let fee_ : Nat = TokenUtils.DEFAULT_FEE;
  private var balances = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);
  private var allowances = HashMap.HashMap<Text, Allowance>(1, Text.equal, Text.hash);

  // ICRC1 methods
  public query func icrc1_name() : async Text { name_ };
  public query func icrc1_symbol() : async Text { symbol_ };
  public query func icrc1_decimals() : async Nat8 { decimals_ };
  public query func icrc1_fee() : async Nat { fee_ };

  public query func icrc1_balance_of(account : Account) : async Nat {
    switch (balances.get(account.owner)) {
      case (?balance) { balance };
      case null { 0 };
    };
  };

  // ICRC2 methods
  public shared (msg) func icrc2_approve(args : ApproveArgs) : async Result.Result<Nat, Text> {
    let key = TokenUtils.getAllowanceKey(msg.caller, args.spender.owner);
    let current_time = Nat64.fromNat(Int.abs(Time.now()));

    // Validate approval using utility function
    let validation_result = TokenUtils.validateApproval(
      args,
      current_time,
      allowances.get(key),
    );

    switch (validation_result) {
      case (#err(e)) { return #err(e) };
      case (#ok()) {
        allowances.put(
          key,
          {
            allowance = args.amount;
            expires_at = args.expires_at;
          },
        );
        #ok(0) // Transaction index (simplified)
      };
    };
  };

  public query func icrc2_allowance(args : AllowanceArgs) : async Allowance {
    let key = TokenUtils.getAllowanceKey(args.account.owner, args.spender.owner);
    switch (allowances.get(key)) {
      case (?allowance) { allowance };
      case null { { allowance = 0; expires_at = null } };
    };
  };
};
