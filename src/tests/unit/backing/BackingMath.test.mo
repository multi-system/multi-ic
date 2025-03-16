import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import Math "../../../multi_backend/backing/BackingMath";
import AmountOperations "../../../multi_backend/financial/AmountOperations";

suite(
  "Backing Math",
  func() {
    let token1 : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    test(
      "calculates eta correctly",
      func() {
        assert (Math.calculateEta(amount(token1, 1000), 100) == 10);
        assert (Math.calculateEta(amount(token1, 2000), 100) == 20);
        assert (Math.calculateEta(amount(token1, 500), 100) == 5);
      },
    );

    test(
      "calculates backing unit correctly",
      func() {
        assert (Math.calculateBackingUnit(amount(token1, 1000), 10) == 100);
        assert (Math.calculateBackingUnit(amount(token1, 500), 10) == 50);
        assert (Math.calculateBackingUnit(amount(token1, 2000), 20) == 100);
        assert (Math.calculateBackingUnit(amount(token1, 100), 34) == 2);
        assert (Math.calculateBackingUnit(amount(token1, 34), 9) == 3);
      },
    );

    test(
      "calculates required backing for single supply unit (phi = 1)",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 100;
        };
        let result = Math.calculateRequiredBacking(amount(token1, 1000), 1000, pair);
        assert (result.value == 100);
        assert (Principal.equal(result.token, token1));
      },
    );

    test(
      "calculates required backing for multiple supply units (phi > 1)",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 100;
        };
        let result = Math.calculateRequiredBacking(amount(token1, 3000), 1000, pair);
        assert (result.value == 300);
        assert (Principal.equal(result.token, token1));
      },
    );

    test(
      "calculates required backing with different backing unit sizes",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 250;
        };
        let result = Math.calculateRequiredBacking(amount(token1, 2000), 1000, pair);
        assert (result.value == 500);
        assert (Principal.equal(result.token, token1));
      },
    );
  },
);
