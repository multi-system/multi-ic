import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import ICRC2 "mo:icrc2-types";
import Types "../../../src/multi_backend/backing_types";
import Validation "../../../src/multi_backend/backing_validation";

suite(
  "Backing Validation",
  func() {
    let token1_principal = Principal.fromText("2vxsx-fae");
    let token2_principal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    let token1_info : Types.TokenInfo = {
      canister_id = token1_principal;
      token = actor (Principal.toText(token1_principal)) : ICRC2.Service;
    };

    let token2_info : Types.TokenInfo = {
      canister_id = token2_principal;
      token = actor (Principal.toText(token2_principal)) : ICRC2.Service;
    };

    test(
      "rejects empty backing",
      func() {
        let backing : [Types.BackingPair] = [];
        switch (Validation.validateBacking(backing)) {
          case (#err(msg)) {
            assert msg == "Backing tokens cannot be empty";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "rejects zero backing units",
      func() {
        let backing : [Types.BackingPair] = [{
          token_info = token1_info;
          backing_unit = 0;
          reserve_quantity = 1000;
        }];

        switch (Validation.validateBacking(backing)) {
          case (#err(msg)) {
            assert msg == "Backing units must be greater than 0";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "rejects zero reserve",
      func() {
        let backing : [Types.BackingPair] = [{
          token_info = token1_info;
          backing_unit = 100;
          reserve_quantity = 0;
        }];

        switch (Validation.validateBacking(backing)) {
          case (#err(msg)) {
            assert msg == "Reserve must be greater than 0";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "rejects duplicate tokens",
      func() {
        let backing : [Types.BackingPair] = [
          {
            token_info = token1_info;
            backing_unit = 100;
            reserve_quantity = 1000;
          },
          {
            token_info = token1_info; // Same token
            backing_unit = 200;
            reserve_quantity = 2000;
          },
        ];

        switch (Validation.validateBacking(backing)) {
          case (#err(msg)) {
            assert msg == "Duplicate token in backing";
          };
          case (#ok()) { assert false };
        };
      },
    );
  },
);
