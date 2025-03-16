import Principal "mo:base/Principal";
import Types "../types/Types";
import Debug "mo:base/Debug";

// TokenUtils provides centralized token validation functions to eliminate
// redundant validation logic across financial modules
module {
  public type Token = Types.Token;
  public type Amount = Types.Amount;

  // Check if two tokens are the same
  public func sameToken(a : Token, b : Token) : Bool {
    Principal.equal(a, b);
  };

  // Check if two amounts have the same token
  public func sameAmountToken(a : Amount, b : Amount) : Bool {
    sameToken(a.token, b.token);
  };

  // Validate tokens match and trap if they don't
  public func validateTokenMatch(a : Token, b : Token) : () {
    if (not sameToken(a, b)) {
      Debug.trap("Token mismatch: Expected " # Principal.toText(a) # " but got " # Principal.toText(b));
    };
  };
};
