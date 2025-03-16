import Types "../types/Types";
import TokenUtils "./TokenUtils";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

module {
  public type Amount = Types.Amount;

  public func new(token : Types.Token, value : Nat) : Amount {
    { token; value };
  };

  public func sameToken(a : Amount, b : Amount) : Bool {
    TokenUtils.sameAmountToken(a, b);
  };

  public func add(a : Amount, b : Amount) : Amount {
    if (not sameToken(a, b)) {
      Debug.trap("Cannot add amounts of different tokens");
    };

    { token = a.token; value = Nat.add(a.value, b.value) };
  };

  /// Checks if subtraction can be performed without underflow
  public func canSubtract(a : Amount, b : Amount) : Bool {
    sameToken(a, b) and a.value >= b.value;
  };

  public func subtract(a : Amount, b : Amount) : Amount {
    if (not sameToken(a, b)) {
      Debug.trap("Cannot subtract amounts of different tokens");
    };

    if (Nat.less(a.value, b.value)) {
      Debug.trap("Insufficient balance for subtraction");
    };

    { token = a.token; value = Nat.sub(a.value, b.value) };
  };

  public func multiplyByScalar(a : Amount, scalar : Nat) : Amount {
    { token = a.token; value = Nat.mul(a.value, scalar) };
  };

  public func divideByScalar(a : Amount, scalar : Nat) : Amount {
    if (scalar == 0) {
      Debug.trap("Division by zero in Amount.divideByScalar");
    };

    { token = a.token; value = Nat.div(a.value, scalar) };
  };

  public func equal(a : Amount, b : Amount) : Bool {
    sameToken(a, b) and Nat.equal(a.value, b.value);
  };

  public func isZero(a : Amount) : Bool {
    a.value == 0;
  };

  public func sum(amounts : [Amount]) : Amount {
    if (amounts.size() == 0) {
      Debug.trap("Cannot sum an empty array of amounts");
    };

    let firstAmount = amounts[0];
    var result = firstAmount;

    for (i in Iter.range(1, amounts.size() - 1)) {
      if (not sameToken(amounts[i], firstAmount)) {
        Debug.trap("Cannot sum amounts with different tokens");
      };
      result := add(result, amounts[i]);
    };

    result;
  };

  public func absoluteDifference(a : Amount, b : Amount) : Amount {
    if (not sameToken(a, b)) {
      Debug.trap("Cannot calculate difference between amounts of different tokens");
    };

    if (a.value >= b.value) {
      return subtract(a, b);
    } else {
      return subtract(b, a);
    };
  };
};
