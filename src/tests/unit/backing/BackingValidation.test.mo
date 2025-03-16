import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import AccountTypes "../../../multi_backend/types/AccountTypes";
import BackingValidation "../../../multi_backend/backing/BackingValidation";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AmountOperations "../../../multi_backend/financial/AmountOperations";

suite(
  "Backing Validation",
  func() {
    let alice : Types.Account = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let multiToken : Types.Token = Principal.fromText("aaaaa-aa");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    var hasInitializedValue = false;
    var backingTokens : [BackingTypes.BackingPair] = [];
    var configValue : BackingTypes.BackingConfig = {
      supplyUnit = 0;
      totalSupply = 0;
      backingPairs = [];
      multiToken = multiToken;
    };

    let mockStore = {
      hasInitialized = func() : Bool { hasInitializedValue };
      getBackingTokens = func() : [BackingTypes.BackingPair] { backingTokens };
      getConfig = func() : BackingTypes.BackingConfig { configValue };
    };

    test(
      "validates supply unit divisibility",
      func() {
        // Test valid case
        assert (BackingValidation.validateSupplyUnitDivisible(amount(multiToken, 100), 10) == #ok());

        // Test zero supply unit
        switch (BackingValidation.validateSupplyUnitDivisible(amount(multiToken, 100), 0)) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Supply unit cannot be zero";
            assert amount == 0;
          };
          case (#err(_)) { assert false };
        };

        // Test indivisible amount
        switch (BackingValidation.validateSupplyUnitDivisible(amount(multiToken, 105), 10)) {
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
        // Test approval before initialization
        assert (BackingValidation.validateTokenApproval(tokenA, mockStore) == #ok());

        // Test after initialization
        hasInitializedValue := true;
        switch (BackingValidation.validateTokenApproval(tokenA, mockStore)) {
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

        // Add tokens to the backing tokens list so they are "approved"
        backingTokens := [
          {
            token = tokenA;
            backingUnit = 10; // Some value, not important for approval check
          },
          {
            token = tokenB;
            backingUnit = 10; // Some value, not important for approval check
          },
        ];

        // Test valid initialization
        let validTokens = [
          {
            token = tokenA;
            backingUnit = 100;
          },
          {
            token = tokenB;
            backingUnit = 50;
          },
        ];

        assert (BackingValidation.validateInitialization(100, validTokens, mockStore) == #ok());

        // Reset backingTokens for other test cases to maintain consistent state
        backingTokens := [
          {
            token = tokenA;
            backingUnit = 10;
          },
          {
            token = tokenB;
            backingUnit = 10;
          },
        ];

        // Test with zero supply unit
        switch (BackingValidation.validateInitialization(0, validTokens, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#InvalidSupplyUnit)) {};
          case (#err(_)) { assert false };
        };

        // Test with zero backing unit
        let invalidTokens = [
          {
            token = tokenA;
            backingUnit = 0; // Invalid backing unit
          },
          {
            token = tokenB;
            backingUnit = 50;
          },
        ];

        switch (BackingValidation.validateInitialization(100, invalidTokens, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#InvalidBackingUnit(token))) {
            assert Principal.equal(token, tokenA);
          };
          case (#err(_)) { assert false };
        };

        // Test with duplicate tokens
        let duplicateTokens = [
          {
            token = tokenA;
            backingUnit = 100;
          },
          {
            token = tokenA; // Duplicate token
            backingUnit = 50;
          },
        ];

        switch (BackingValidation.validateInitialization(100, duplicateTokens, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#DuplicateToken(token))) {
            assert Principal.equal(token, tokenA);
          };
          case (#err(_)) { assert false };
        };

        // Add test for unapproved token
        let unapprovedToken : Types.Token = Principal.fromText("aaaaa-aa");
        let unapprovedTokens = [{
          token = unapprovedToken;
          backingUnit = 100;
        }];

        switch (BackingValidation.validateInitialization(100, unapprovedTokens, mockStore)) {
          case (#ok()) { assert false };
          case (#err(#TokenNotApproved(token))) {
            assert Principal.equal(token, unapprovedToken);
          };
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates backing token transfer",
      func() {
        let initVAState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();
        let virtualAccounts = VirtualAccounts.VirtualAccounts(initVAState);

        backingTokens := [{
          token = tokenA;
          backingUnit = 50;
        }];

        // Test with sufficient balance
        virtualAccounts.mint(alice, amount(tokenA, 1000));

        switch (
          BackingValidation.validateBackingTokenTransfer(
            amount(multiToken, 1000),
            alice,
            100,
            backingTokens,
            virtualAccounts,
          )
        ) {
          case (#ok(transfers)) {
            assert transfers.size() == 1;
            assert Principal.equal(transfers[0].token, tokenA);
            assert transfers[0].value == 500; // 50 * (1000/100)
          };
          case (#err(_)) { assert false };
        };

        // Test with insufficient balance
        virtualAccounts.burn(alice, amount(tokenA, 600));
        switch (
          BackingValidation.validateBackingTokenTransfer(
            amount(multiToken, 1000),
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
        let initVAState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();
        let virtualAccounts = VirtualAccounts.VirtualAccounts(initVAState);

        // Test with insufficient balance
        switch (
          BackingValidation.validateRedeemBalance(
            amount(tokenA, 100),
            alice,
            virtualAccounts,
          )
        ) {
          case (#ok()) { assert false };
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert required == 100;
            assert balance == 0;
          };
          case (#err(_)) { assert false };
        };

        // Test with sufficient balance
        virtualAccounts.mint(alice, amount(tokenA, 100));
        assert (
          BackingValidation.validateRedeemBalance(
            amount(tokenA, 100),
            alice,
            virtualAccounts,
          ) == #ok()
        );
      },
    );

    test(
      "validates supply change",
      func() {
        let currentSupply = amount(multiToken, 1000);

        // Test valid increase
        assert (
          BackingValidation.validateSupplyChange(
            amount(multiToken, 100),
            true,
            currentSupply,
            100,
          ) == #ok()
        );

        // Test valid decrease
        assert (
          BackingValidation.validateSupplyChange(
            amount(multiToken, 500),
            false,
            currentSupply,
            100,
          ) == #ok()
        );

        // Test invalid decrease (more than current supply)
        switch (
          BackingValidation.validateSupplyChange(
            amount(multiToken, 1500),
            false,
            currentSupply,
            100,
          )
        ) {
          case (#ok()) { assert false };
          case (#err(#InvalidSupplyChange({ currentSupply; requestedChange; reason }))) {
            assert currentSupply == 1000;
            assert requestedChange == 1500;
            assert reason == "Cannot decrease supply by more than current supply";
          };
          case (#err(_)) { assert false };
        };

        // Test indivisible amount
        switch (
          BackingValidation.validateSupplyChange(
            amount(multiToken, 155),
            true,
            currentSupply,
            100,
          )
        ) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 155;
          };
          case (#err(_)) { assert false };
        };
      },
    );

    test(
      "validates redeem amount",
      func() {
        let totalSupply = amount(multiToken, 1000);

        // Test valid redeem amount
        assert (
          BackingValidation.validateRedeemAmount(
            amount(multiToken, 500),
            totalSupply,
            100,
          ) == #ok()
        );

        // Test redeem amount greater than total supply
        switch (
          BackingValidation.validateRedeemAmount(
            amount(multiToken, 1500),
            totalSupply,
            100,
          )
        ) {
          case (#ok()) { assert false };
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Cannot redeem more than total supply";
            assert amount == 1500;
          };
          case (#err(_)) { assert false };
        };

        // Test indivisible redeem amount
        switch (
          BackingValidation.validateRedeemAmount(
            amount(multiToken, 155),
            totalSupply,
            100,
          )
        ) {
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
