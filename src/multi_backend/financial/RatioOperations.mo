import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Types "../types/Types";
import AmountOperations "../financial/AmountOperations";
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

  // Calculate ratio between two Amounts
  public func calculateAmountRatio(numerator : Types.Amount, denominator : Types.Amount) : Types.Ratio {
    if (not AmountOperations.sameToken(numerator, denominator)) {
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
  public func calculateProportionOfAmount(
    part : Types.Amount,
    whole : Types.Amount,
    total : Types.Amount,
  ) : Types.Amount {
    if (
      not AmountOperations.sameToken(part, whole) or
      not AmountOperations.sameToken(part, total)
    ) {
      Debug.trap("Cannot calculate proportion for different tokens");
    };

    {
      token = total.token;
      value = calculateProportion(part.value, whole.value, total.value);
    };
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

  // Private helper for proportion calculation
  private func calculateProportion(
    part : Nat,
    whole : Nat,
    total : Nat,
  ) : Nat {
    if (whole == 0) {
      return 0;
    };
    Nat.div(Nat.mul(part, total), whole);
  };
};
