import Principal "mo:base/Principal";

module {
  public type Account = Principal;

  public type TransferArgs = {
    from : Account;
    to : Account;
    token : Principal;
    amount : Nat;
  };
};
