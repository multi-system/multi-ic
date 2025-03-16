import Principal "mo:base/Principal";

module {
  public type Token = Principal;
  public type Account = Principal;

  public type Amount = {
    token : Token;
    value : Nat;
  };

  public type Ratio = {
    value : Nat;
  };

  public type Price = {
    baseToken : Token;
    quoteToken : Token;
    value : Ratio;
  };
};
