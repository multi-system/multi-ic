import ICRC2 "mo:icrc2-types";
import Principal "mo:base/Principal";

module {
  public type TokenInfo = {
    canister_id : Principal;
    token : ICRC2.Service;
  };

  public type BackingPair = {
    token_info : TokenInfo;
    units : Nat;
    reserve : Nat;
  };

  public type BackingConfig = {
    supply_unit : Nat;
    total_supply : Nat;
    backing_pairs : [BackingPair];
  };
};
