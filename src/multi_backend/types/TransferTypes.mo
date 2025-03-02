import Types "Types";

module {
  public type TransferArgs = {
    from : Types.Account;
    to : Types.Account;
    token : Types.Token;
    amount : Nat;
  };
};
