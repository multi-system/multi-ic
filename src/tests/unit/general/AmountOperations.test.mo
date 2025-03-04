import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import AmountOperations "../../../multi_backend/financial/AmountOperations";
import Result "mo:base/Result";

suite(
  "Amount Operations",
  func() {
    // Test tokens
    let token1 : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let token2 : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    test(
      "creates a new amount",
      func() {
        let a = AmountOperations.new(token1, 1000);
        assert (Principal.equal(a.token, token1));
        assert (a.value == 1000);
      },
    );

    test(
      "checks if tokens are the same",
      func() {
        let a = amount(token1, 100);
        let b = amount(token1, 200);
        let c = amount(token2, 100);

        assert (AmountOperations.sameToken(a, b) == true);
        assert (AmountOperations.sameToken(a, c) == false);
      },
    );

    test(
      "adds amounts with same token",
      func() {
        let a = amount(token1, 100);
        let b = amount(token1, 200);
        let result = AmountOperations.add(a, b);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 300);
      },
    );

    test(
      "subtracts amounts with same token when sufficient balance",
      func() {
        let a = amount(token1, 300);
        let b = amount(token1, 100);

        switch (AmountOperations.subtract(a, b)) {
          case (#ok(result)) {
            assert (Principal.equal(result.token, token1));
            assert (result.value == 200);
          };
          case (#err(_)) {
            assert (false); // Should not reach here
          };
        };
      },
    );

    test(
      "returns error when subtracting with insufficient balance",
      func() {
        let a = amount(token1, 100);
        let b = amount(token1, 200);

        switch (AmountOperations.subtract(a, b)) {
          case (#ok(_)) {
            assert (false); // Should not reach here
          };
          case (#err(error)) {
            switch (error) {
              case (#InsufficientBalance(data)) {
                assert (Principal.equal(data.token, token1));
                assert (data.required == 200);
                assert (data.balance == 100);
              };
              case (_) {
                assert (false); // Should not reach here
              };
            };
          };
        };
      },
    );

    test(
      "multiplies amount by scalar",
      func() {
        let a = amount(token1, 100);
        let result = AmountOperations.multiplyByScalar(a, 5);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 500);
      },
    );

    test(
      "divides amount by scalar",
      func() {
        let a = amount(token1, 100);
        let result = AmountOperations.divideByScalar(a, 4);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 25);
      },
    );

    test(
      "checks if amounts are equal",
      func() {
        let a = amount(token1, 100);
        let b = amount(token1, 100);
        let c = amount(token1, 200);
        let d = amount(token2, 100);

        assert (AmountOperations.equal(a, b) == true);
        assert (AmountOperations.equal(a, c) == false);
        assert (AmountOperations.equal(a, d) == false);
      },
    );

    test(
      "checks if amount is zero",
      func() {
        let a = amount(token1, 0);
        let b = amount(token1, 100);

        assert (AmountOperations.isZero(a) == true);
        assert (AmountOperations.isZero(b) == false);
      },
    );

    test(
      "calculates sum of amounts",
      func() {
        let a = amount(token1, 100);
        let b = amount(token1, 200);
        let c = amount(token1, 300);

        let result = AmountOperations.sum([a, b, c]);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 600);
      },
    );

    test(
      "division rounds down toward 0",
      func() {
        let a = amount(token1, 10);
        let result = AmountOperations.divideByScalar(a, 3);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 3); // 10 / 3 = 3.333... rounds to 3
      },
    );

    test(
      "divides odd numbers correctly",
      func() {
        let a = amount(token1, 101);
        let result = AmountOperations.divideByScalar(a, 2);

        assert (Principal.equal(result.token, token1));
        assert (result.value == 50); // 101 / 2 = 50.5 rounds to 50
      },
    );
  },
);
