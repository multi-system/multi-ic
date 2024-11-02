import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import ICRC2 "mo:icrc2-types";
import Types "../../../src/multi_backend/backing_types";
import Math "../../../src/multi_backend/backing_math";

suite(
  "Backing Math",
  func() {
    let token1_principal = Principal.fromText("2vxsx-fae");
    let token1_info : Types.TokenInfo = {
      canister_id = token1_principal;
      token = actor (Principal.toText(token1_principal)) : ICRC2.Service;
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
          supply_unit = 100; // minimum issuable amount
          total_supply = 1000; // eta will be 10
          backing_pairs = [{
            token_info = token1_info;
            backing_unit = 100; // backing token requirement for one supply unit
            reserve_quantity = 1000;
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
          supply_unit = 100;
          total_supply = 1000; // eta will be 10
          backing_pairs = [{
            token_info = token1_info;
            backing_unit = 150; // incorrect since reserve_quantity/eta should equal backing_unit
            reserve_quantity = 1000;
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
          token_info = token1_info;
          backing_unit = 100;
          reserve_quantity = 1000;
        };

        switch (Math.calculateRequiredBacking(1000, 1000, pair)) {
          // amount = one supply unit
          case (#ok(required)) {
            // phi = 1, so required = phi * backing_unit = 1 * 100 = 100
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
          token_info = token1_info;
          backing_unit = 100;
          reserve_quantity = 1000;
        };

        switch (Math.calculateRequiredBacking(3000, 1000, pair)) {
          // amount = 3 supply units
          case (#ok(required)) {
            // phi = 3, so required = phi * backing_unit = 3 * 100 = 300
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
          token_info = token1_info;
          backing_unit = 100;
          reserve_quantity = 1000;
        };

        switch (Math.calculateRequiredBacking(1500, 1000, pair)) {
          // 1500 is not multiple of supply_unit=1000
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
          token_info = token1_info;
          backing_unit = 250;
          reserve_quantity = 1000;
        };

        switch (Math.calculateRequiredBacking(2000, 1000, pair)) {
          // amount = 2 supply units
          case (#ok(required)) {
            // phi = 2, so required = phi * backing_unit = 2 * 250 = 500
            assert required == 500;
          };
          case (#err(_)) assert false;
        };
      },
    );
  },
);
