import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import ICRC2 "mo:icrc2-types";
import Types "../../../src/multi_backend/BackingTypes";
import Math "../../../src/multi_backend/BackingMath";

suite(
  "Backing Math",
  func() {
    let token1Principal = Principal.fromText("2vxsx-fae");
    let token1Info : Types.TokenInfo = {
      canisterId = token1Principal;
      token = actor (Principal.toText(token1Principal)) : ICRC2.Service;
    };

    test(
      "calculates eta correctly",
      func() {
        switch (Math.calculateEta(1000, 100)) {
          case (#err(msg)) { assert false };
          case (#ok(eta)) { assert eta == 10 };
        };
      },
    );

    test(
      "validates correct backing ratios",
      func() {
        let config : Types.BackingConfig = {
          supplyUnit = 100; // minimum issuable amount
          totalSupply = 1000; // eta will be 10
          backingPairs = [{
            tokenInfo = token1Info;
            backingUnit = 100; // backing token requirement for one supply unit
            reserveQuantity = 1000;
          }];
        };

        switch (Math.validateBackingRatios(config)) {
          case (#err(msg)) {
            Debug.print(msg);
            assert false;
          };
          case (#ok()) { assert true };
        };
      },
    );

    test(
      "rejects invalid backing ratios",
      func() {
        let config : Types.BackingConfig = {
          supplyUnit = 100;
          totalSupply = 1000; // eta will be 10
          backingPairs = [{
            tokenInfo = token1Info;
            backingUnit = 150; // incorrect since reserveQuantity/eta should equal backingUnit
            reserveQuantity = 1000;
          }];
        };

        switch (Math.validateBackingRatios(config)) {
          case (#err(msg)) { assert msg == "Invalid backing ratio" };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "calculates required backing for single supply unit (phi = 1)",
      func() {
        let pair : Types.BackingPair = {
          tokenInfo = token1Info;
          backingUnit = 100;
          reserveQuantity = 1000;
        };

        switch (Math.calculateRequiredBacking(1000, 1000, pair)) {
          case (#ok(required)) {
            // phi = 1, so required = phi * backingUnit = 1 * 100 = 100
            assert required == 100;
          };
          case (#err(_)) assert false;
        };
      },
    );

    test(
      "calculates required backing for multiple supply units (phi > 1)",
      func() {
        let pair : Types.BackingPair = {
          tokenInfo = token1Info;
          backingUnit = 100;
          reserveQuantity = 1000;
        };

        switch (Math.calculateRequiredBacking(3000, 1000, pair)) {
          case (#ok(required)) {
            // phi = 3, so required = phi * backingUnit = 3 * 100 = 300
            assert required == 300;
          };
          case (#err(_)) assert false;
        };
      },
    );

    test(
      "rejects backing calculation when amount not multiple of supply unit",
      func() {
        let pair : Types.BackingPair = {
          tokenInfo = token1Info;
          backingUnit = 100;
          reserveQuantity = 1000;
        };

        switch (Math.calculateRequiredBacking(1500, 1000, pair)) {
          case (#ok(_)) assert false;
          case (#err(msg)) {
            assert msg == "Amount must be multiple of supply unit";
          };
        };
      },
    );

    test(
      "calculates required backing with different backing unit sizes",
      func() {
        let pair : Types.BackingPair = {
          tokenInfo = token1Info;
          backingUnit = 250;
          reserveQuantity = 1000;
        };

        switch (Math.calculateRequiredBacking(2000, 1000, pair)) {
          case (#ok(required)) {
            // phi = 2, so required = phi * backingUnit = 2 * 250 = 500
            assert required == 500;
          };
          case (#err(_)) assert false;
        };
      },
    );
  },
);
