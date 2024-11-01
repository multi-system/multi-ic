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
          supply_unit = 100;
          total_supply = 1000; // eta will be 10
          backing_pairs = [{
            token_info = token1_info;
            units = 100; // correct since 1000/10 = 100
            reserve = 1000;
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
            units = 150; // incorrect since 1000/10 = 100
            reserve = 1000;
          }];
        };

        switch (Math.validateBackingRatios(config)) {
          case (#err(msg)) { assert msg == "Invalid backing ratio" };
          case (#ok()) { assert false };
        };
      },
    );
  },
);
