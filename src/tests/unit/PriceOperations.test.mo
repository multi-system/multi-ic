import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/Types";
import PriceOperations "../../multi_backend/financial/PriceOperations";
import AmountOperations "../../multi_backend/financial/AmountOperations";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

suite(
  "Price Operations",
  func() {
    // Test tokens
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let tokenC : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    // Fixed-point precision used in the PriceOperations module
    let PRECISION : Nat = 1_000_000_000;

    // Helper to create price objects
    let price = func(baseToken : Types.Token, quoteToken : Types.Token, value : Nat) : Types.Price {
      { baseToken; quoteToken; value };
    };

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    test(
      "creates a new price",
      func() {
        let p = PriceOperations.new(tokenA, tokenB, 1_000_000_000); // 1.0 in fixed-point
        assert (Principal.equal(p.baseToken, tokenA));
        assert (Principal.equal(p.quoteToken, tokenB));
        assert (p.value == 1_000_000_000);
      },
    );

    test(
      "creates a price from a natural number with scaling",
      func() {
        let p = PriceOperations.fromNat(tokenA, tokenB, 2); // 2.0
        assert (Principal.equal(p.baseToken, tokenA));
        assert (Principal.equal(p.quoteToken, tokenB));
        assert (p.value == 2_000_000_000); // 2 * 10^9
      },
    );

    test(
      "checks if prices are compatible",
      func() {
        let p1 = price(tokenA, tokenB, 1_000_000_000);
        let p2 = price(tokenA, tokenB, 2_000_000_000);
        let p3 = price(tokenB, tokenA, 1_000_000_000);
        let p4 = price(tokenA, tokenC, 1_000_000_000);

        assert (PriceOperations.isCompatible(p1, p2) == true);
        assert (PriceOperations.isCompatible(p1, p3) == false);
        assert (PriceOperations.isCompatible(p1, p4) == false);
      },
    );

    test(
      "calculates inverse price",
      func() {
        let p = price(tokenA, tokenB, 2_000_000_000); // 2.0 in fixed-point
        let inverted = PriceOperations.inverse(p);

        assert (Principal.equal(inverted.baseToken, tokenB));
        assert (Principal.equal(inverted.quoteToken, tokenA));
        assert (inverted.value == 500_000_000); // 0.5 in fixed-point
      },
    );

    test(
      "calculates value of an amount using price",
      func() {
        let a = amount(tokenA, 500);
        let p = price(tokenA, tokenB, 2_000_000_000); // 2.0 in fixed-point
        let result = PriceOperations.calculateValue(a, p);

        assert (Principal.equal(result.token, tokenB));
        assert (result.value == 1_000); // 500 * 2.0 = 1000
      },
    );

    test(
      "compares prices - equal",
      func() {
        let p1 = price(tokenA, tokenB, 1_000_000_000);
        let p2 = price(tokenA, tokenB, 1_000_000_000);

        assert (PriceOperations.compare(p1, p2) == #equal);
      },
    );

    test(
      "compares prices - less",
      func() {
        let p1 = price(tokenA, tokenB, 1_000_000_000);
        let p2 = price(tokenA, tokenB, 2_000_000_000);

        assert (PriceOperations.compare(p1, p2) == #less);
      },
    );

    test(
      "compares prices - greater",
      func() {
        let p1 = price(tokenA, tokenB, 2_000_000_000);
        let p2 = price(tokenA, tokenB, 1_000_000_000);

        assert (PriceOperations.compare(p1, p2) == #greater);
      },
    );

    test(
      "finds minimum price in array",
      func() {
        let p1 = price(tokenA, tokenB, 1_000_000_000);
        let p2 = price(tokenA, tokenB, 2_000_000_000);
        let p3 = price(tokenA, tokenB, 500_000_000);

        let minPrice = PriceOperations.min([p1, p2, p3]);

        assert (Principal.equal(minPrice.baseToken, tokenA));
        assert (Principal.equal(minPrice.quoteToken, tokenB));
        assert (minPrice.value == 500_000_000);
      },
    );

    test(
      "multiplies two prices correctly",
      func() {
        // A/B price = 2.0
        let pAB = price(tokenA, tokenB, 2_000_000_000);

        // B/C price = 3.0
        let pBC = price(tokenB, tokenC, 3_000_000_000);

        let pAC = PriceOperations.multiply(pAB, pBC);

        assert (Principal.equal(pAC.baseToken, tokenA));
        assert (Principal.equal(pAC.quoteToken, tokenC));
        assert (pAC.value == 6_000_000_000); // 2.0 * 3.0 = 6.0
      },
    );

    test(
      "multiplies prices with fractional results",
      func() {
        // A/B price = 2.5
        let pAB = price(tokenA, tokenB, 2_500_000_000);

        // B/C price = 0.4
        let pBC = price(tokenB, tokenC, 400_000_000);

        let pAC = PriceOperations.multiply(pAB, pBC);

        assert (Principal.equal(pAC.baseToken, tokenA));
        assert (Principal.equal(pAC.quoteToken, tokenC));
        assert (pAC.value == 1_000_000_000); // 2.5 * 0.4 = 1.0
      },
    );

    test(
      "adds percentage to price",
      func() {
        let p = price(tokenA, tokenB, 2_000_000_000); // 2.0

        // Add 10% (1000 basis points)
        let result = PriceOperations.addPercentage(p, 1000);

        assert (Principal.equal(result.baseToken, tokenA));
        assert (Principal.equal(result.quoteToken, tokenB));
        assert (result.value == 2_200_000_000); // 2.0 * 1.1 = 2.2
      },
    );

    test(
      "chain of price operations works correctly",
      func() {
        // Token A to Token B price = 2.0
        let pAB = price(tokenA, tokenB, 2_000_000_000);

        // Token B to Token C price = 3.0
        let pBC = price(tokenB, tokenC, 3_000_000_000);

        // Convert amount from A to B
        let amountA = amount(tokenA, 100);
        let amountB = PriceOperations.calculateValue(amountA, pAB);

        // Then convert from B to C
        let amountC = PriceOperations.calculateValue(amountB, pBC);

        assert (Principal.equal(amountC.token, tokenC));
        assert (amountC.value == 600); // 100 * 2.0 * 3.0 = 600
      },
    );

    test(
      "handles price calculation with large numbers",
      func() {
        // Large amount
        let largeAmount = amount(tokenA, 1_000_000_000);

        // Price 1.5
        let p = price(tokenA, tokenB, 1_500_000_000);

        let result = PriceOperations.calculateValue(largeAmount, p);

        assert (Principal.equal(result.token, tokenB));
        assert (result.value == 1_500_000_000); // 1_000_000_000 * 1.5 = 1_500_000_000
      },
    );
  },
);
