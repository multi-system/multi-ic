import Types "../types/Types";
import AmountOperations "./AmountOperations";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Result "mo:base/Result";
import Error "../error/Error";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

module {
  public type Price = Types.Price;
  public type Amount = Types.Amount;

  // Fixed-point precision constant for price operations
  private let PRECISION : Nat = 1_000_000_000;

  public func new(baseToken : Types.Token, quoteToken : Types.Token, value : Nat) : Price {
    { baseToken; quoteToken; value };
  };

  // Create a price with a raw value (already scaled by PRECISION)
  public func newScaled(baseToken : Types.Token, quoteToken : Types.Token, value : Nat) : Price {
    { baseToken; quoteToken; value };
  };

  // Create a price from a natural number and apply scaling
  public func fromNat(baseToken : Types.Token, quoteToken : Types.Token, value : Nat) : Price {
    { baseToken; quoteToken; value = Nat.mul(value, PRECISION) };
  };

  public func isCompatible(a : Price, b : Price) : Bool {
    Principal.equal(a.baseToken, b.baseToken) and Principal.equal(a.quoteToken, b.quoteToken);
  };

  public func inverse(p : Price) : Price {
    if (p.value == 0) {
      Debug.trap("Cannot invert zero price");
    };

    // Using a fixed-point approach: result = PRECISION^2 / value
    let numerator = Nat.mul(PRECISION, PRECISION);
    let value = Nat.div(numerator, p.value);

    {
      baseToken = p.quoteToken;
      quoteToken = p.baseToken;
      value = value;
    };
  };

  public func calculateValue(amount : Amount, price : Price) : Amount {
    if (not Principal.equal(amount.token, price.baseToken)) {
      Debug.trap("Token mismatch: amount token doesn't match price base token");
    };

    // Multiply by price and then divide by PRECISION to maintain correct scaling
    let rawValue = Nat.mul(amount.value, price.value);
    let scaledValue = Nat.div(rawValue, PRECISION);

    { token = price.quoteToken; value = scaledValue };
  };

  public func compare(a : Price, b : Price) : { #less; #equal; #greater } {
    if (not isCompatible(a, b)) {
      Debug.trap("Cannot compare prices for different token pairs");
    };

    if (a.value < b.value) return #less;
    if (a.value > b.value) return #greater;
    #equal;
  };

  public func min(prices : [Price]) : Price {
    if (prices.size() == 0) {
      Debug.trap("Cannot find minimum of empty price array");
    };

    var minPrice = prices[0];

    for (i in Iter.range(1, prices.size() - 1)) {
      let current = prices[i];

      if (not isCompatible(current, minPrice)) {
        Debug.trap("Cannot compare prices for different token pairs");
      };

      if (current.value < minPrice.value) {
        minPrice := current;
      };
    };

    minPrice;
  };

  // Helper function to convert a scaled price value to a human-readable Float
  public func toFloat(p : Price) : Float {
    let floatValue = Float.fromInt(p.value);
    let floatPrecision = Float.fromInt(PRECISION);
    floatValue / floatPrecision;
  };

  // Create a new price by multiplying two compatible prices
  // If p1 is A/B and p2 is B/C, result is A/C
  public func multiply(p1 : Price, p2 : Price) : Price {
    if (not Principal.equal(p1.quoteToken, p2.baseToken)) {
      Debug.trap("Incompatible price pair for multiplication: quote of first price must match base of second price");
    };

    let rawValue = Nat.mul(p1.value, p2.value);
    let scaledValue = Nat.div(rawValue, PRECISION);

    {
      baseToken = p1.baseToken;
      quoteToken = p2.quoteToken;
      value = scaledValue;
    };
  };

  // Adds a percentage to the price (e.g., for calculating fees)
  // percentage is in basis points (e.g., 100 = 1%, 10000 = 100%)
  public func addPercentage(p : Price, basisPoints : Nat) : Price {
    let factor = PRECISION + Nat.div(Nat.mul(basisPoints, PRECISION), 10000);
    let newValue = Nat.div(Nat.mul(p.value, factor), PRECISION);

    {
      baseToken = p.baseToken;
      quoteToken = p.quoteToken;
      value = newValue;
    };
  };
};
