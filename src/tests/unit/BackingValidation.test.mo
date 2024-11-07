import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import ICRC2 "mo:icrc2-types";
import Types "../../../src/multi_backend/BackingTypes";
import Validation "../../../src/multi_backend/BackingValidation";

suite(
  "Backing Validation",
  func() {
    let token1Principal = Principal.fromText("2vxsx-fae");
    let token2Principal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    let token1Info : Types.TokenInfo = {
      canisterId = token1Principal;
      token = actor (Principal.toText(token1Principal)) : ICRC2.Service;
    };

    let token2Info : Types.TokenInfo = {
      canisterId = token2Principal;
      token = actor (Principal.toText(token2Principal)) : ICRC2.Service;
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
          tokenInfo = token1Info;
          backingUnit = 0;
          reserveQuantity = 1000;
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
          tokenInfo = token1Info;
          backingUnit = 100;
          reserveQuantity = 0;
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
            tokenInfo = token1Info;
            backingUnit = 100;
            reserveQuantity = 1000;
          },
          {
            tokenInfo = token1Info; // Same token
            backingUnit = 200;
            reserveQuantity = 2000;
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

    test(
      "validates backing config",
      func() {
        let config : Types.BackingConfig = {
          supplyUnit = 0;
          totalSupply = 1000;
          backingPairs = [];
        };

        switch (Validation.validateBackingConfig(config)) {
          case (#err(msg)) {
            assert msg == "Supply unit cannot be zero";
          };
          case (#ok()) { assert false };
        };
      },
    );
  },
);
