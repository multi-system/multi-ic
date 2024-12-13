import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/BackingTypes";
import Validation "../../multi_backend/backing/BackingValidation";

suite(
  "Backing Validation",
  func() {
    let token1Principal = Principal.fromText("2vxsx-fae");
    let token2Principal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

    let token1Info : Types.TokenInfo = {
      canisterId = token1Principal;
    };

    let token2Info : Types.TokenInfo = {
      canisterId = token2Principal;
    };

    test(
      "rejects empty backing",
      func() {
        let backing : [Types.BackingPair] = [];
        switch (Validation.validateStructure(backing)) {
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

        switch (Validation.validateStructure(backing)) {
          case (#err(msg)) {
            assert msg == "Backing units must be greater than 0";
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

        switch (Validation.validateStructure(backing)) {
          case (#err(msg)) {
            assert msg == "Duplicate token in backing";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "validates config correctly",
      func() {
        let config : Types.BackingConfig = {
          supplyUnit = 0;
          totalSupply = 1000;
          backingPairs = [];
        };

        switch (Validation.validateConfig(config)) {
          case (#err(msg)) {
            assert msg == "Supply unit cannot be zero";
          };
          case (#ok()) { assert false };
        };
      },
    );
  },
);
