import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/BackingTypes";
import Math "../../multi_backend/backing/BackingMath";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

suite(
  "Backing Math",
  func() {
    let token1Principal = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let token1Info : Types.TokenInfo = {
      canisterId = token1Principal;
    };

    let initState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
    var virtualAccounts : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager(initState);

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
          supplyUnit = 100;
          totalSupply = 1000; // eta = 10
          backingPairs = [{
            tokenInfo = token1Info;
            backingUnit = 100; // reserveQuantity/eta = 1000/10 = 100
          }];
        };

        // Set up the virtual account balance to match what we expect
        virtualAccounts.mint(systemAccount, token1Principal, 1000);

        switch (Math.validateBackingRatios(config, virtualAccounts, systemAccount)) {
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
          totalSupply = 1000; // eta = 10
          backingPairs = [{
            tokenInfo = token1Info;
            backingUnit = 150; // incorrect: reserveQuantity/eta = 1000/10 = 100 != 150
          }];
        };

        // Set up the virtual account balance
        virtualAccounts.mint(systemAccount, token1Principal, 1000);

        switch (Math.validateBackingRatios(config, virtualAccounts, systemAccount)) {
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
