import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Types "../types/Types";
import TokenUtils "./TokenUtils";
import Float "mo:base/Float";

module {
  // Scaling factor for ratio calculations (10^9)
  private let SCALING_FACTOR : Nat = 1_000_000_000;

  // Create a ratio from a decimal value (e.g., 5 becomes 5.0)
  public func fromDecimal(value : Nat) : Types.Ratio {
    { value = value * SCALING_FACTOR };
  };

  // Create a ratio from basis points (e.g., 500 becomes 0.05)
  public func fromBasisPoints(basisPoints : Nat) : Types.Ratio {
    { value = basisPoints * SCALING_FACTOR / 10000 };
  };

  // Create a ratio from two natural numbers (numerator/denominator)
  public func fromNats(numerator : Nat, denominator : Nat) : Types.Ratio {
    if (denominator == 0) {
      Debug.trap("Division by zero in RatioOperations.fromNats");
    };

    let scaledNumerator = Nat.mul(numerator, SCALING_FACTOR);
    { value = Nat.div(scaledNumerator, denominator) };
  };

  // Convert an amount from one token to another using a ratio
  public func convertToToken(
    amount : Types.Amount,
    toToken : Types.Token,
    ratio : Types.Ratio,
  ) : Types.Amount {
    {
      token = toToken;
      value = applyToAmount(amount, ratio).value;
    };
  };

  // Calculate ratio between two Amounts
  public func calculateAmountRatio(numerator : Types.Amount, denominator : Types.Amount) : Types.Ratio {
    if (not TokenUtils.sameAmountToken(numerator, denominator)) {
      Debug.trap("Cannot calculate ratio between different tokens");
    };

    if (denominator.value == 0) {
      Debug.trap("Division by zero in calculateAmountRatio");
    };

    let scaledNumerator = Nat.mul(numerator.value, SCALING_FACTOR);
    { value = Nat.div(scaledNumerator, denominator.value) };
  };

  // Apply a ratio to an Amount
  public func applyToAmount(amount : Types.Amount, ratio : Types.Ratio) : Types.Amount {
    {
      token = amount.token;
      value = Nat.div(Nat.mul(amount.value, ratio.value), SCALING_FACTOR);
    };
  };

  // Calculate proportion of one Amount in another, scaled to a total Amount
  // Uses Ratio to maintain precision in intermediate calculations
  public func calculateProportionOfAmount(
    part : Types.Amount,
    whole : Types.Amount,
    total : Types.Amount,
  ) : Types.Amount {
    if (
      not TokenUtils.sameAmountToken(part, whole) or
      not TokenUtils.sameAmountToken(whole, total)
    ) {
      Debug.trap("Cannot calculate proportion for different tokens");
    };

    if (whole.value == 0) {
      return { token = total.token; value = 0 };
    };

    // 1. Calculate the ratio of part to whole
    let proportionRatio = calculateAmountRatio(part, whole);

    // 2. Apply this ratio to the total amount
    applyToAmount(total, proportionRatio);
  };

  // Add two ratios
  public func add(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    { value = a.value + b.value };
  };

  // Subtract one ratio from another
  public func subtract(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    if (a.value < b.value) {
      Debug.trap("Negative ratio result in subtract");
    };
    { value = a.value - b.value };
  };

  // Multiply two ratios
  public func multiply(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    { value = Nat.div(Nat.mul(a.value, b.value), SCALING_FACTOR) };
  };

  // Divide one ratio by another (a/b)
  public func divide(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    if (b.value == 0) {
      Debug.trap("Division by zero in Ratio.divide");
    };

    // To divide a/b, we multiply a by the inverse of b
    multiply(a, inverse(b));
  };

  // Inverse of a ratio (1/ratio)
  public func inverse(ratio : Types.Ratio) : Types.Ratio {
    if (ratio.value == 0) {
      Debug.trap("Cannot invert zero ratio");
    };
    let numerator = Nat.mul(SCALING_FACTOR, SCALING_FACTOR);
    { value = Nat.div(numerator, ratio.value) };
  };

  // Compare two ratios
  public func compare(a : Types.Ratio, b : Types.Ratio) : {
    #less;
    #equal;
    #greater;
  } {
    if (a.value < b.value) return #less;
    if (a.value > b.value) return #greater;
    #equal;
  };

  // Min and max operations
  public func min(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    if (a.value <= b.value) a else b;
  };

  public func max(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    if (a.value >= b.value) a else b;
  };

  // Convert ratio to Float for display/debugging
  public func toFloat(ratio : Types.Ratio) : Float {
    let floatValue = Float.fromInt(ratio.value);
    let floatPrecision = Float.fromInt(SCALING_FACTOR);
    floatValue / floatPrecision;
  };

  // Calculate the absolute difference between two ratios
  public func absoluteDifference(a : Types.Ratio, b : Types.Ratio) : Types.Ratio {
    if (a.value >= b.value) { { value = a.value - b.value } } else {
      { value = b.value - a.value };
    };
  };

  // Returns true if ratios a and b are within the specified tolerance
  public func withinTolerance(a : Types.Ratio, b : Types.Ratio, tolerance : Types.Ratio) : Bool {
    let difference = absoluteDifference(a, b);
    difference.value <= tolerance.value;
  };
};
