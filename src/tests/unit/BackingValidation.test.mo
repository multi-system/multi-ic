import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/BackingTypes";
import BackingValidation "../../multi_backend/backing/BackingValidation";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Error "../../multi_backend/types/Error";
import Result "mo:base/Result";

suite(
  "Backing Validation",
  func() {
    let alice = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

    var hasInitializedValue = false;
    var backingTokens : [Types.BackingPair] = [];
    var configValue : Types.BackingConfig = {
      supplyUnit = 0;
      totalSupply = 0;
      backingPairs = [];
      multiToken = { canisterId = Principal.fromText("aaaaa-aa") };
    };

    let mockStore = {
      hasInitialized = func() : Bool { hasInitializedValue };
      getBackingTokens = func() : [Types.BackingPair] { backingTokens };
      getConfig = func() : Types.BackingConfig { configValue };
    };

    test(
      "validates supply unit divisibility",
      func() {
        // Test valid case
        assert (BackingValidation.validateSupplyUnitDivisible(100, 10) == #ok());

        // Test zero supply unit
        switch (BackingValidation.validateSupplyUnitDivisible(100, 0)) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Supply unit cannot be zero";
            assert amount == 0;
          };
          case (#err(_)) { assert false };
        };

        // Test indivisible amount
        switch (BackingValidation.validateSupplyUnitDivisible(105, 10)) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 105;
          };
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates token approval",
      func() {
        let tokenInfo = { canisterId = tokenA };

        // Test approval before initialization
        assert (BackingValidation.validateTokenApproval(tokenInfo, mockStore) == #ok());

        // Test after initialization
        hasInitializedValue := true;
        switch (BackingValidation.validateTokenApproval(tokenInfo, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#AlreadyInitialized)) {};
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates initialization",
      func() {
        hasInitializedValue := false;
        backingTokens := [{
          tokenInfo = { canisterId = tokenA };
          backingUnit = 100;
        }];

        // Test valid initialization
        assert (BackingValidation.validateInitialization(100, 1000, mockStore) == #ok());

        // Test with zero supply unit
        switch (BackingValidation.validateInitialization(0, 1000, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#InvalidSupplyUnit)) {};
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates initial amounts",
      func() {
        let initVAState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
        let virtualAccounts = VirtualAccounts.VirtualAccountManager(initVAState);

        backingTokens := [{
          tokenInfo = { canisterId = tokenA };
          backingUnit = 100;
        }];

        // Test with insufficient balance
        let initialAmounts = [(tokenA, 1000)];
        switch (BackingValidation.validateInitialAmounts(initialAmounts, backingTokens, alice, virtualAccounts)) {
          case (#ok(_)) { assert false };
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert required == 1000;
            assert balance == 0;
          };
          case (#err(_)) { assert false };
        };

        // Test with sufficient balance
        virtualAccounts.mint(alice, tokenA, 1000);
        switch (BackingValidation.validateInitialAmounts(initialAmounts, backingTokens, alice, virtualAccounts)) {
          case (#ok(transfers)) {
            assert transfers.size() == 1;
            assert Principal.equal(transfers[0].0, tokenA);
            assert transfers[0].1 == 1000;
          };
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates backing token transfer",
      func() {
        let initVAState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
        let virtualAccounts = VirtualAccounts.VirtualAccountManager(initVAState);

        backingTokens := [{
          tokenInfo = { canisterId = tokenA };
          backingUnit = 50;
        }];

        // Test with sufficient balance
        virtualAccounts.mint(alice, tokenA, 1000);

        switch (
          BackingValidation.validateBackingTokenTransfer(
            1000,
            alice,
            100,
            backingTokens,
            virtualAccounts,
          )
        ) {
          case (#ok(transfers)) {
            assert transfers.size() == 1;
            assert Principal.equal(transfers[0].0, tokenA);
            assert transfers[0].1 == 500; // 50 * (1000/100)
          };
          case (#err(_)) { assert false };
        };

        // Test with insufficient balance
        virtualAccounts.burn(alice, tokenA, 600);
        switch (
          BackingValidation.validateBackingTokenTransfer(
            1000,
            alice,
            100,
            backingTokens,
            virtualAccounts,
          )
        ) {
          case (#ok(_)) { assert false };
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert required == 500;
            assert balance == 400;
          };
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates redeem balance",
      func() {
        let initVAState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
        let virtualAccounts = VirtualAccounts.VirtualAccountManager(initVAState);

        // Test with insufficient balance
        switch (BackingValidation.validateRedeemBalance(100, alice, tokenA, virtualAccounts)) {
          case (#ok()) { assert false };
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert required == 100;
            assert balance == 0;
          };
          case (#err(_)) { assert false };
        };

        // Test with sufficient balance
        virtualAccounts.mint(alice, tokenA, 100);
        assert (BackingValidation.validateRedeemBalance(100, alice, tokenA, virtualAccounts) == #ok());
      },
    );

    test(
      "validates supply change",
      func() {
        // Test valid increase
        assert (BackingValidation.validateSupplyChange(100, true, 1000, 100) == #ok());

        // Test valid decrease
        assert (BackingValidation.validateSupplyChange(500, false, 1000, 100) == #ok());

        // Test invalid decrease (more than current supply)
        switch (BackingValidation.validateSupplyChange(1500, false, 1000, 100)) {
          case (#ok()) { assert false };
          case (#err(#InvalidSupplyChange({ currentSupply; requestedChange; reason }))) {
            assert currentSupply == 1000;
            assert requestedChange == 1500;
            assert reason == "Cannot decrease supply by more than current supply";
          };
          case (#err(_)) { assert false };
        };

        // Test indivisible amount
        switch (BackingValidation.validateSupplyChange(155, true, 1000, 100)) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 155;
          };
          case (#err(_)) { assert false };
        };
      },
    );
  },
);
