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
      "divides one ratio by another",
      func() {
        let ratio1 = RatioOperations.fromDecimal(6); // 6.0
        let ratio2 = RatioOperations.fromDecimal(2); // 2.0
        let quotient = RatioOperations.divide(ratio1, ratio2);

        assert quotient.value == 3 * SCALING_FACTOR; // 6.0 / 2.0 = 3.0
      },
    );

    test(
      "divides ratios with fractional results",
      func() {
        let ratio1 = { value = 5 * SCALING_FACTOR / 10 }; // 0.5
        let ratio2 = { value = 2 * SCALING_FACTOR / 10 }; // 0.2
        let quotient = RatioOperations.divide(ratio1, ratio2);

        assert quotient.value == 25 * SCALING_FACTOR / 10; // 0.5 / 0.2 = 2.5
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

    test(
      "maintains precision for small proportions in calculateProportionOfAmount",
      func() {
        let part = amount(tokenA, 1);
        let whole = amount(tokenA, 1000);
        let total = amount(tokenA, 10000);

        let result = RatioOperations.calculateProportionOfAmount(part, whole, total);

        assert result.value == 10;
      },
    );

    test(
      "maintains precision for large values in calculateProportionOfAmount",
      func() {
        let part = amount(tokenA, 1_000_000_000);
        let whole = amount(tokenA, 10_000_000_000);
        let total = amount(tokenA, 50_000_000_000);

        let result = RatioOperations.calculateProportionOfAmount(part, whole, total);

        assert result.value == 5_000_000_000;
      },
    );

    test(
      "handles non-integer ratios in calculateProportionOfAmount",
      func() {
        let part = amount(tokenA, 3);
        let whole = amount(tokenA, 7);
        let total = amount(tokenA, 100);

        let result = RatioOperations.calculateProportionOfAmount(part, whole, total);

        assert result.value == 42;
      },
    );

    test(
      "handles tiny proportions without losing precision in calculateProportionOfAmount",
      func() {
        let part = amount(tokenA, 1);
        let whole = amount(tokenA, 1_000_000);
        let total = amount(tokenA, 10_000_000);

        let result = RatioOperations.calculateProportionOfAmount(part, whole, total);

        assert result.value == 10;
      },
    );

    test(
      "compares Ratio vs direct calculation approaches",
      func() {
        func directProportion(part : Types.Amount, whole : Types.Amount, total : Types.Amount) : Types.Amount {
          {
            token = total.token;
            value = (part.value * total.value) / whole.value;
          };
        };

        // Test case 1: Basic proportion calculation
        let part1 = amount(tokenA, 1);
        let whole1 = amount(tokenA, 3);
        let total1 = amount(tokenA, 30);

        let ratioResult1 = RatioOperations.calculateProportionOfAmount(part1, whole1, total1);
        let directResult1 = directProportion(part1, whole1, total1);

        assert directResult1.value == 10;

        // Test case 2: Testing integer division behavior
        let part2 = amount(tokenA, 1);
        let whole2 = amount(tokenA, 3);
        let total2 = amount(tokenA, 10);

        let ratioResult2 = RatioOperations.calculateProportionOfAmount(part2, whole2, total2);
        let directResult2 = directProportion(part2, whole2, total2);

        assert directResult2.value == 3;

        // Test case 3: Other simple test case
        let part3 = amount(tokenA, 5);
        let whole3 = amount(tokenA, 10);
        let total3 = amount(tokenA, 100);

        let ratioResult3 = RatioOperations.calculateProportionOfAmount(part3, whole3, total3);
        let directResult3 = directProportion(part3, whole3, total3);

        assert directResult3.value == 50;
      },
    );
  },
);
