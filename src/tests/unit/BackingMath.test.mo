import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/Types";
import BackingTypes "../../multi_backend/types/BackingTypes";
import Math "../../multi_backend/backing/BackingMath";

suite(
  "Backing Math",
  func() {
    let token1 : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");

    test(
      "calculates eta correctly",
      func() {
        assert (Math.calculateEta(1000, 100) == 10);
        assert (Math.calculateEta(2000, 100) == 20);
        assert (Math.calculateEta(500, 100) == 5);
      },
    );

    test(
      "calculates backing unit correctly",
      func() {
        assert (Math.calculateBackingUnit(1000, 10) == 100);
        assert (Math.calculateBackingUnit(500, 10) == 50);
        assert (Math.calculateBackingUnit(2000, 20) == 100);
      },
    );

    test(
      "calculates required backing for single supply unit (phi = 1)",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 100;
        };
        assert (Math.calculateRequiredBacking(1000, 1000, pair) == 100);
      },
    );

    test(
      "calculates required backing for multiple supply units (phi > 1)",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 100;
        };
        assert (Math.calculateRequiredBacking(3000, 1000, pair) == 300);
      },
    );

    test(
      "calculates required backing with different backing unit sizes",
      func() {
        let pair : BackingTypes.BackingPair = {
          token = token1;
          backingUnit = 250;
        };
        assert (Math.calculateRequiredBacking(2000, 1000, pair) == 500);
      },
    );
  },
);
