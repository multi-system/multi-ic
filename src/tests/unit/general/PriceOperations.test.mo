import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import PriceOperations "../../../multi_backend/financial/PriceOperations";
import RatioOperations "../../../multi_backend/financial/RatioOperations";
import AmountOperations "../../../multi_backend/financial/AmountOperations";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

suite(
  "Price Operations",
  func() {
    // Test tokens
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let tokenC : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    // Fixed-point precision used in the RatioOperations module
    let SCALING_FACTOR : Nat = 1_000_000_000;

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    test(
      "creates a new price from a ratio",
      func() {
        let ratio = RatioOperations.fromDecimal(1);
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);
        assert Principal.equal(p.baseToken, tokenA);
        assert Principal.equal(p.quoteToken, tokenB);
        assert p.value.value == SCALING_FACTOR;
      },
    );

    test(
      "creates a price from a decimal value",
      func() {
        let ratio = RatioOperations.fromDecimal(2);
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);
        assert Principal.equal(p.baseToken, tokenA);
        assert Principal.equal(p.quoteToken, tokenB);
        assert p.value.value == 2 * SCALING_FACTOR;
      },
    );

    test(
      "checks if prices are compatible",
      func() {
        let ratio1 = RatioOperations.fromDecimal(1);
        let ratio2 = RatioOperations.fromDecimal(2);

        let p1 = PriceOperations.fromRatio(tokenA, tokenB, ratio1);
        let p2 = PriceOperations.fromRatio(tokenA, tokenB, ratio2);
        let p3 = PriceOperations.fromRatio(tokenB, tokenA, ratio1);
        let p4 = PriceOperations.fromRatio(tokenA, tokenC, ratio1);

        assert (PriceOperations.isCompatible(p1, p2) == true);
        assert (PriceOperations.isCompatible(p1, p3) == false);
        assert (PriceOperations.isCompatible(p1, p4) == false);
      },
    );

    test(
      "calculates inverse price",
      func() {
        let ratio = RatioOperations.fromDecimal(2);
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);
        let inverted = PriceOperations.inverse(p);

        assert Principal.equal(inverted.baseToken, tokenB);
        assert Principal.equal(inverted.quoteToken, tokenA);
        assert inverted.value.value == SCALING_FACTOR / 2; // 0.5 in fixed-point
      },
    );

    test(
      "calculates value of an amount using price",
      func() {
        let a = amount(tokenA, 500);
        let ratio = RatioOperations.fromDecimal(2);
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);
        let result = PriceOperations.calculateValue(a, p);

        assert Principal.equal(result.token, tokenB);
        assert result.value == 1_000; // 500 * 2.0 = 1000
      },
    );

    test(
      "compares prices - equal",
      func() {
        let ratio = RatioOperations.fromDecimal(1);
        let p1 = PriceOperations.fromRatio(tokenA, tokenB, ratio);
        let p2 = PriceOperations.fromRatio(tokenA, tokenB, ratio);

        assert (PriceOperations.compare(p1, p2) == #equal);
      },
    );

    test(
      "compares prices - less",
      func() {
        let ratio1 = RatioOperations.fromDecimal(1);
        let ratio2 = RatioOperations.fromDecimal(2);
        let p1 = PriceOperations.fromRatio(tokenA, tokenB, ratio1);
        let p2 = PriceOperations.fromRatio(tokenA, tokenB, ratio2);

        assert (PriceOperations.compare(p1, p2) == #less);
      },
    );

    test(
      "compares prices - greater",
      func() {
        let ratio1 = RatioOperations.fromDecimal(2);
        let ratio2 = RatioOperations.fromDecimal(1);
        let p1 = PriceOperations.fromRatio(tokenA, tokenB, ratio1);
        let p2 = PriceOperations.fromRatio(tokenA, tokenB, ratio2);

        assert (PriceOperations.compare(p1, p2) == #greater);
      },
    );

    test(
      "finds minimum price in array",
      func() {
        let ratio1 = RatioOperations.fromDecimal(1);
        let ratio2 = RatioOperations.fromDecimal(2);
        let ratio3 = { value = SCALING_FACTOR / 2 }; // 0.5

        let p1 = PriceOperations.fromRatio(tokenA, tokenB, ratio1);
        let p2 = PriceOperations.fromRatio(tokenA, tokenB, ratio2);
        let p3 = PriceOperations.fromRatio(tokenA, tokenB, ratio3);

        let minPrice = PriceOperations.min([p1, p2, p3]);

        assert Principal.equal(minPrice.baseToken, tokenA);
        assert Principal.equal(minPrice.quoteToken, tokenB);
        assert minPrice.value.value == SCALING_FACTOR / 2;
      },
    );

    test(
      "multiplies two prices correctly",
      func() {
        // A/B price = 2.0
        let ratioAB = RatioOperations.fromDecimal(2);
        let pAB = PriceOperations.fromRatio(tokenA, tokenB, ratioAB);

        // B/C price = 3.0
        let ratioBC = RatioOperations.fromDecimal(3);
        let pBC = PriceOperations.fromRatio(tokenB, tokenC, ratioBC);

        let pAC = PriceOperations.multiply(pAB, pBC);

        assert Principal.equal(pAC.baseToken, tokenA);
        assert Principal.equal(pAC.quoteToken, tokenC);
        assert pAC.value.value == 6 * SCALING_FACTOR; // 2.0 * 3.0 = 6.0
      },
    );

    test(
      "multiplies prices with fractional results",
      func() {
        // A/B price = 2.5
        let ratioAB = { value = 25 * SCALING_FACTOR / 10 }; // 2.5
        let pAB = PriceOperations.fromRatio(tokenA, tokenB, ratioAB);

        // B/C price = 0.4
        let ratioBC = { value = 4 * SCALING_FACTOR / 10 }; // 0.4
        let pBC = PriceOperations.fromRatio(tokenB, tokenC, ratioBC);

        let pAC = PriceOperations.multiply(pAB, pBC);

        assert Principal.equal(pAC.baseToken, tokenA);
        assert Principal.equal(pAC.quoteToken, tokenC);
        assert pAC.value.value == SCALING_FACTOR; // 2.5 * 0.4 = 1.0
      },
    );

    test(
      "adds fee to price",
      func() {
        let ratio = RatioOperations.fromDecimal(2);
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);

        // Add 10% fee
        let feeRatio = RatioOperations.fromBasisPoints(1000); // 10%
        let result = PriceOperations.addFee(p, feeRatio);

        assert Principal.equal(result.baseToken, tokenA);
        assert Principal.equal(result.quoteToken, tokenB);
        assert result.value.value == 22 * SCALING_FACTOR / 10; // 2.0 * 1.1 = 2.2
      },
    );

    test(
      "chain of price operations works correctly",
      func() {
        // Token A to Token B price = 2.0
        let ratioAB = RatioOperations.fromDecimal(2);
        let pAB = PriceOperations.fromRatio(tokenA, tokenB, ratioAB);

        // Token B to Token C price = 3.0
        let ratioBC = RatioOperations.fromDecimal(3);
        let pBC = PriceOperations.fromRatio(tokenB, tokenC, ratioBC);

        // Convert amount from A to B
        let amountA = amount(tokenA, 100);
        let amountB = PriceOperations.calculateValue(amountA, pAB);

        // Then convert from B to C
        let amountC = PriceOperations.calculateValue(amountB, pBC);

        assert Principal.equal(amountC.token, tokenC);
        assert amountC.value == 600; // 100 * 2.0 * 3.0 = 600
      },
    );

    test(
      "handles price calculation with large numbers",
      func() {
        // Large amount
        let largeAmount = amount(tokenA, 1_000_000_000);

        // Price 1.5
        let ratio = { value = 15 * SCALING_FACTOR / 10 }; // 1.5
        let p = PriceOperations.fromRatio(tokenA, tokenB, ratio);

        let result = PriceOperations.calculateValue(largeAmount, p);

        assert Principal.equal(result.token, tokenB);
        assert result.value == 1_500_000_000; // 1_000_000_000 * 1.5 = 1_500_000_000
      },
    );
  },
);
