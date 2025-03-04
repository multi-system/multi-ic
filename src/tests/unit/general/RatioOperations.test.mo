import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import RatioOperations "../../../multi_backend/financial/RatioOperations";
import AmountOperations "../../../multi_backend/financial/AmountOperations";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

suite(
  "Ratio Operations",
  func() {
    // Test tokens for Amount tests
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    // Fixed-point precision used in the RatioOperations module
    let SCALING_FACTOR : Nat = 1_000_000_000;

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    test(
      "creates a ratio from decimal value",
      func() {
        let ratio = RatioOperations.fromDecimal(5);
        assert ratio.value == 5 * SCALING_FACTOR;
      },
    );

    test(
      "creates a ratio from basis points",
      func() {
        let ratio = RatioOperations.fromBasisPoints(500); // 5%
        assert ratio.value == 5 * SCALING_FACTOR / 100; // 0.05 in fixed-point
      },
    );

    test(
      "calculates ratio between two amounts",
      func() {
        let a1 = amount(tokenA, 500);
        let a2 = amount(tokenA, 200);
        let ratio = RatioOperations.calculateAmountRatio(a1, a2);

        assert ratio.value == 25 * SCALING_FACTOR / 10; // 2.5 in fixed-point
      },
    );

    test(
      "applies ratio to an amount",
      func() {
        let a = amount(tokenA, 100);
        let ratio = RatioOperations.fromDecimal(2); // 2.0
        let result = RatioOperations.applyToAmount(a, ratio);

        assert Principal.equal(result.token, tokenA);
        assert result.value == 200; // 100 * 2.0 = 200
      },
    );

    test(
      "calculates proportion of amounts",
      func() {
        let part = amount(tokenA, 30);
        let whole = amount(tokenA, 100);
        let total = amount(tokenA, 500);

        let result = RatioOperations.calculateProportionOfAmount(part, whole, total);

        assert Principal.equal(result.token, tokenA);
        assert result.value == 150; // (30/100) * 500 = 150
      },
    );

    test(
      "adds two ratios",
      func() {
        let ratio1 = RatioOperations.fromDecimal(2);
        let ratio2 = RatioOperations.fromDecimal(3);
        let sum = RatioOperations.add(ratio1, ratio2);

        assert sum.value == 5 * SCALING_FACTOR; // 2.0 + 3.0 = 5.0
      },
    );

    test(
      "subtracts one ratio from another",
      func() {
        let ratio1 = RatioOperations.fromDecimal(5);
        let ratio2 = RatioOperations.fromDecimal(3);
        let diff = RatioOperations.subtract(ratio1, ratio2);

        assert diff.value == 2 * SCALING_FACTOR; // 5.0 - 3.0 = 2.0
      },
    );

    test(
      "multiplies two ratios",
      func() {
        let ratio1 = RatioOperations.fromDecimal(2);
        let ratio2 = RatioOperations.fromDecimal(3);
        let product = RatioOperations.multiply(ratio1, ratio2);

        assert product.value == 6 * SCALING_FACTOR; // 2.0 * 3.0 = 6.0
      },
    );

    test(
      "multiplies ratios with fractional results",
      func() {
        let ratio1 = { value = 25 * SCALING_FACTOR / 10 }; // 2.5
        let ratio2 = { value = 4 * SCALING_FACTOR / 10 }; // 0.4
        let product = RatioOperations.multiply(ratio1, ratio2);

        assert product.value == SCALING_FACTOR; // 2.5 * 0.4 = 1.0
      },
    );

    test(
      "calculates inverse of a ratio",
      func() {
        let ratio = RatioOperations.fromDecimal(2);
        let inverseRatio = RatioOperations.inverse(ratio);

        assert inverseRatio.value == SCALING_FACTOR / 2; // 1/2 = 0.5
      },
    );

    test(
      "compares ratios - equal",
      func() {
        let ratio1 = RatioOperations.fromDecimal(2);
        let ratio2 = RatioOperations.fromDecimal(2);

        assert RatioOperations.compare(ratio1, ratio2) == #equal;
      },
    );

    test(
      "compares ratios - less",
      func() {
        let ratio1 = RatioOperations.fromDecimal(1);
        let ratio2 = RatioOperations.fromDecimal(2);

        assert RatioOperations.compare(ratio1, ratio2) == #less;
      },
    );

    test(
      "compares ratios - greater",
      func() {
        let ratio1 = RatioOperations.fromDecimal(3);
        let ratio2 = RatioOperations.fromDecimal(2);

        assert RatioOperations.compare(ratio1, ratio2) == #greater;
      },
    );

    test(
      "finds minimum of two ratios",
      func() {
        let ratio1 = RatioOperations.fromDecimal(3);
        let ratio2 = RatioOperations.fromDecimal(2);
        let min = RatioOperations.min(ratio1, ratio2);

        assert min.value == 2 * SCALING_FACTOR;
      },
    );

    test(
      "finds maximum of two ratios",
      func() {
        let ratio1 = RatioOperations.fromDecimal(3);
        let ratio2 = RatioOperations.fromDecimal(2);
        let max = RatioOperations.max(ratio1, ratio2);

        assert max.value == 3 * SCALING_FACTOR;
      },
    );

    test(
      "handles ratio operations correctly",
      func() {
        // Create ratios with decimals
        let ratio1 = { value = 25 * SCALING_FACTOR / 10 }; // 2.5
        let ratio2 = { value = 33 * SCALING_FACTOR / 100 }; // 0.33

        // Test addition
        let sum = RatioOperations.add(ratio1, ratio2);
        // 2.5 + 0.33 = 2.83
        assert (283 * SCALING_FACTOR / 100) - 1 <= sum.value and sum.value <= (283 * SCALING_FACTOR / 100) + 1;

        // Test multiplication
        let product = RatioOperations.multiply(ratio1, ratio2);
        // 2.5 * 0.33 = 0.825
        assert (825 * SCALING_FACTOR / 1000) - 1 <= product.value and product.value <= (825 * SCALING_FACTOR / 1000) + 1;
      },
    );

    test(
      "applies ratio to small and large amounts correctly",
      func() {
        let smallAmount = amount(tokenA, 1);
        let largeAmount = amount(tokenA, 1_000_000_000);
        let ratio = RatioOperations.fromDecimal(2);

        let smallResult = RatioOperations.applyToAmount(smallAmount, ratio);
        let largeResult = RatioOperations.applyToAmount(largeAmount, ratio);

        assert smallResult.value == 2; // 1 * 2.0 = 2
        assert largeResult.value == 2_000_000_000; // 1,000,000,000 * 2.0 = 2,000,000,000
      },
    );

    test(
      "calculates ratio of very different amounts",
      func() {
        let smallAmount = amount(tokenA, 1);
        let largeAmount = amount(tokenA, 1_000_000_000);

        let smallToLargeRatio = RatioOperations.calculateAmountRatio(smallAmount, largeAmount);
        let largeToSmallRatio = RatioOperations.calculateAmountRatio(largeAmount, smallAmount);

        // 1/1,000,000,000 = 0.000000001
        assert smallToLargeRatio.value == 1;

        // 1,000,000,000/1 = 1,000,000,000
        assert largeToSmallRatio.value == 1_000_000_000 * SCALING_FACTOR;
      },
    );

    test(
      "converts ratio to float for display",
      func() {
        let ratio = RatioOperations.fromDecimal(2);
        let floatValue = RatioOperations.toFloat(ratio);

        assert floatValue == 2.0;
      },
    );
  },
);
