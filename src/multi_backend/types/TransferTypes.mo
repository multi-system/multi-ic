import Types "Types";

module {
  public type TransferArgs = {
    from : Types.Account;
    to : Types.Account;
    amount : Types.Amount;
  };
};
