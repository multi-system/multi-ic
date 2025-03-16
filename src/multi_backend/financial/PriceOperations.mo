import Types "../types/Types";
import TokenUtils "./TokenUtils";
import RatioOperations "./RatioOperations";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

module {
  public type Price = Types.Price;
  public type Amount = Types.Amount;
  public type Ratio = Types.Ratio;

  // Create a new price from a ratio
  public func fromRatio(baseToken : Types.Token, quoteToken : Types.Token, ratio : Ratio) : Price {
    {
      baseToken;
      quoteToken;
      value = ratio;
    };
  };

  // Check if two prices are compatible (same token pair)
  public func isCompatible(a : Price, b : Price) : Bool {
    TokenUtils.sameToken(a.baseToken, b.baseToken) and TokenUtils.sameToken(a.quoteToken, b.quoteToken);
  };

  // Calculate the inverse of a price (B/A from A/B)
  public func inverse(p : Price) : Price {
    {
      baseToken = p.quoteToken;
      quoteToken = p.baseToken;
      value = RatioOperations.inverse(p.value);
    };
  };

  // Calculate quote token amount from base token amount using price
  public func calculateValue(amount : Amount, price : Price) : Amount {
    TokenUtils.validateTokenMatch(amount.token, price.baseToken);

    {
      token = price.quoteToken;
      value = RatioOperations.applyToAmount(amount, price.value).value;
    };
  };

  // Compare two prices
  public func compare(a : Price, b : Price) : { #less; #equal; #greater } {
    if (not isCompatible(a, b)) {
      Debug.trap("Cannot compare prices for different token pairs");
    };

    RatioOperations.compare(a.value, b.value);
  };

  // Find minimum price from an array
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

      if (RatioOperations.compare(current.value, minPrice.value) == #less) {
        minPrice := current;
      };
    };

    minPrice;
  };

  // Convert price to human-readable float
  public func toFloat(p : Price) : Float {
    RatioOperations.toFloat(p.value);
  };

  // Multiply two compatible prices (A/B * B/C = A/C)
  public func multiply(p1 : Price, p2 : Price) : Price {
    if (not TokenUtils.sameToken(p1.quoteToken, p2.baseToken)) {
      Debug.trap("Incompatible price pair for multiplication");
    };

    {
      baseToken = p1.baseToken;
      quoteToken = p2.quoteToken;
      value = RatioOperations.multiply(p1.value, p2.value);
    };
  };

  // Add fee to price using a ratio
  public func addFee(p : Price, feeRatio : Ratio) : Price {
    // Create a ratio representing (1 + feeRatio)
    let unitRatio = RatioOperations.fromDecimal(1);
    let adjustedRatio = RatioOperations.add(unitRatio, feeRatio);

    {
      baseToken = p.baseToken;
      quoteToken = p.quoteToken;
      value = RatioOperations.multiply(p.value, adjustedRatio);
    };
  };

  // Convert an amount using a price, specifying the target token type
  public func convertAmount(
    amount : Types.Amount,
    price : Types.Price,
    direction : { #toBase; #toQuote },
  ) : Types.Amount {
    switch (direction) {
      case (#toBase) {
        if (TokenUtils.sameToken(amount.token, price.quoteToken)) {
          // Convert from quote to base token using the inverse price ratio
          let inversePrice = inverse(price);
          return RatioOperations.convertToToken(amount, price.baseToken, inversePrice.value);
        } else if (TokenUtils.sameToken(amount.token, price.baseToken)) {
          return amount; // Already in base token
        };
      };
      case (#toQuote) {
        if (TokenUtils.sameToken(amount.token, price.baseToken)) {
          // Convert from base to quote token using the price ratio
          return RatioOperations.convertToToken(amount, price.quoteToken, price.value);
        } else if (TokenUtils.sameToken(amount.token, price.quoteToken)) {
          return amount; // Already in quote token
        };
      };
    };

    Debug.trap(
      "Incompatible token conversion: cannot convert " #
      Principal.toText(amount.token) #
      " using price between " #
      Principal.toText(price.baseToken) #
      " and " #
      Principal.toText(price.quoteToken)
    );
  };
};
