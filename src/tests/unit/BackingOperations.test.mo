import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/BackingTypes";
import BackingStore "../../multi_backend/backing/BackingStore";
import BackingOperations "../../multi_backend/backing/BackingOperations";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import BackingMath "../../multi_backend/backing/BackingMath";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Error "../../multi_backend/types/Error";

suite(
  "Backing Operations",
  func() {
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let multiTokenLedger = Principal.fromText("qhbym-qaaaa-aaaaa-aaafq-cai");
    let caller = Principal.fromText("aaaaa-aa");

    let tokenAInfo : Types.TokenInfo = { canisterId = tokenA };
    let tokenBInfo : Types.TokenInfo = { canisterId = tokenB };
    let multiTokenInfo : Types.TokenInfo = { canisterId = multiTokenLedger };

    let createTestEnv = func() : (BackingStore.BackingStore, BackingOperations.BackingOperationsImpl, VirtualAccounts.VirtualAccountManager) {
      let state : Types.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 0;
          totalSupply = 0;
          backingPairs = [];
          multiToken = { canisterId = Principal.fromText("aaaaa-aa") };
        };
      };

      let store = BackingStore.BackingStore(state);
      let initVAState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
      let virtualAccounts = VirtualAccounts.VirtualAccountManager(initVAState);

      let ops = BackingOperations.BackingOperationsImpl(
        store,
        virtualAccounts,
        systemAccount,
      );

      (store, ops, virtualAccounts);
    };

    let setupSystem = func(
      store : BackingStore.BackingStore,
      ops : BackingOperations.BackingOperationsImpl,
      va : VirtualAccounts.VirtualAccountManager,
      initialAmountA : Nat,
      initialAmountB : Nat,
      redeemToZero : Bool,
    ) {
      // Clear any existing balances by burning them
      let existingBalanceA = va.getBalance(caller, tokenA);
      let existingBalanceB = va.getBalance(caller, tokenB);

      if (existingBalanceA > 0) {
        va.burn(caller, tokenA, existingBalanceA);
      };
      if (existingBalanceB > 0) {
        va.burn(caller, tokenB, existingBalanceB);
      };

      // Mint fresh amounts
      va.mint(caller, tokenA, initialAmountA);
      va.mint(caller, tokenB, initialAmountB);

      assert (ops.approveToken(caller, tokenAInfo) == #ok());
      assert (ops.approveToken(caller, tokenBInfo) == #ok());

      let initialAmounts = [
        (tokenA, initialAmountA),
        (tokenB, initialAmountB),
      ];

      assert (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo) == #ok());
      let multiBalance = va.getBalance(caller, multiTokenLedger);
      assert (multiBalance == 1000);

      if (redeemToZero) {
        assert (va.getBalance(caller, multiTokenLedger) == 1000);
        assert (ops.processRedeem(caller, 1000) == #ok());
        assert (store.getTotalSupply() == 0);

        // Clear remaining balances after redeem
        let remainingBalanceA = va.getBalance(caller, tokenA);
        let remainingBalanceB = va.getBalance(caller, tokenB);

        if (remainingBalanceA > 0) {
          va.burn(caller, tokenA, remainingBalanceA);
        };
        if (remainingBalanceB > 0) {
          va.burn(caller, tokenB, remainingBalanceB);
        };
      };
    };

    test(
      "initializes with single token successfully",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (ops.approveToken(caller, tokenAInfo) == #ok());
        va.mint(caller, tokenA, 1000);

        let initialAmounts = [(tokenA, 1000)];

        switch (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            assert (store.getSupplyUnit() == 100);
            assert (store.getTotalSupply() == 1000);
            assert (va.getBalance(systemAccount, tokenA) == 1000);
            assert (va.getBalance(caller, multiTokenLedger) == 1000);
          };
        };
      },
    );

    test(
      "prevents double initialization",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (ops.approveToken(caller, tokenAInfo) == #ok());
        va.mint(caller, tokenA, 1000);
        let initialAmounts = [(tokenA, 1000)];
        assert (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo) == #ok());

        switch (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo)) {
          case (#err(#AlreadyInitialized)) {};
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with unapproved token",
      func() {
        let (store, ops, va) = createTestEnv();
        let unauthorizedToken = Principal.fromText("aaaaa-aa");

        va.mint(caller, unauthorizedToken, 1000);
        let initialAmounts = [(unauthorizedToken, 1000)];

        switch (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo)) {
          case (#err(#TokenNotApproved(token))) {
            assert Principal.equal(token, unauthorizedToken);
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with insufficient balance",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (ops.approveToken(caller, tokenAInfo) == #ok());
        va.mint(caller, tokenA, 500);

        let initialAmounts = [(tokenA, 1000)];

        switch (ops.processInitialize(caller, initialAmounts, 100, 1000, multiTokenInfo)) {
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert required == 1000;
            assert balance == 500;
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with invalid supply unit ratio",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (ops.approveToken(caller, tokenAInfo) == #ok());
        va.mint(caller, tokenA, 1000);

        let initialAmounts = [(tokenA, 1000)];

        switch (ops.processInitialize(caller, initialAmounts, 100, 150, multiTokenInfo)) {
          case (#err(#InvalidSupplyUnit)) {};
          case _ { assert false };
        };
      },
    );

    test(
      "handles issue with sufficient balance",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        va.mint(caller, tokenA, 200);
        va.mint(caller, tokenB, 100);

        switch (ops.processIssue(caller, 100)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            assert (va.getBalance(systemAccount, tokenA) == backingTokens[0].backingUnit);
            assert (va.getBalance(systemAccount, tokenB) == backingTokens[1].backingUnit);
            let config = store.getConfig();
            assert (va.getBalance(caller, config.multiToken.canisterId) == 100);
          };
        };
      },
    );

    test(
      "fails issue with insufficient balance",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        let backingTokens = store.getBackingTokens();

        va.mint(caller, tokenA, 50);
        va.mint(caller, tokenB, 50);

        switch (ops.processIssue(caller, 100)) {
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert (store.getTotalSupply() == 0);
            assert (va.getBalance(systemAccount, tokenA) == 0);
            assert (va.getBalance(systemAccount, tokenB) == 0);
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails issue with unaligned supply unit",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        va.mint(caller, tokenA, 200);
        va.mint(caller, tokenB, 100);

        switch (ops.processIssue(caller, 150)) {
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 150;
          };
          case _ { assert false };
        };
      },
    );

    test(
      "handles complete issue/redeem cycle",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        let initialCallerA = va.getBalance(caller, tokenA);
        let initialCallerB = va.getBalance(caller, tokenB);

        va.mint(caller, tokenA, 200);
        va.mint(caller, tokenB, 100);
        assert (ops.processIssue(caller, 100) == #ok());

        let issuedSystemA = va.getBalance(systemAccount, tokenA);
        let issuedSystemB = va.getBalance(systemAccount, tokenB);

        assert (ops.processRedeem(caller, 100) == #ok());

        assert (va.getBalance(systemAccount, tokenA) == 0);
        assert (va.getBalance(systemAccount, tokenB) == 0);
        assert (va.getBalance(caller, tokenA) == initialCallerA + 200);
        assert (va.getBalance(caller, tokenB) == initialCallerB + 100);
        assert (store.getTotalSupply() == 0);
      },
    );

    test(
      "handles complex sequence of supply changes with ratio verification",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        // Initial state setup with proper backing
        va.mint(caller, tokenA, 400); // Initial reserve for Token A
        va.mint(caller, tokenB, 200); // Initial reserve for Token B

        // 1. First issue sets up our reserve quantities
        assert (ops.processIssue(caller, 200) == #ok());

        let initialTokens = store.getBackingTokens();
        assert initialTokens[0].backingUnit == 100;
        assert initialTokens[1].backingUnit == 50;
        assert (va.getBalance(systemAccount, tokenA) == 200);
        assert (va.getBalance(systemAccount, tokenB) == 100);

        // 2. Process supply increase (which decreases backing ratios since tokens are spread thinner)
        switch (ops.processSupplyIncrease(400)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            // Verify new backing units decreased due to higher supply
            assert backingTokens[0].backingUnit == 33; // 200/6 = 33 (decreased from 100)
            assert backingTokens[1].backingUnit == 16; // 100/6 = 16 (decreased from 50)
          };
        };

        // 3. Issue with new lower ratios
        assert (ops.processIssue(caller, 100) == #ok());

        // Verify transfers used new lower ratios
        assert va.getBalance(caller, tokenA) == 167; // 200 - 33
        assert va.getBalance(caller, tokenB) == 84; // 100 - 16
        assert va.getBalance(systemAccount, tokenA) == 233; // 200 + 33
        assert va.getBalance(systemAccount, tokenB) == 116; // 100 + 16

        // 4. Process supply decrease (which increases backing ratios)
        switch (ops.processSupplyDecrease(300)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            // Verify new backing units increased due to lower supply
            assert backingTokens[0].backingUnit == 58; // 233/4 = 58 (increased from 33)
            assert backingTokens[1].backingUnit == 29; // 116/4 = 29 (increased from 16)
          };
        };

        // 5. Redeem with new higher ratios
        assert (ops.processRedeem(caller, 100) == #ok());

        // Verify transfers used new higher ratios
        assert va.getBalance(caller, tokenA) == 225; // 167 + 58
        assert va.getBalance(caller, tokenB) == 113; // 84 + 29
        assert va.getBalance(systemAccount, tokenA) == 175; // 233 - 58
        assert va.getBalance(systemAccount, tokenB) == 87; // 116 - 29

        // Verify ratios maintained throughout
        let finalTokens = store.getBackingTokens();
        assert (finalTokens[0].backingUnit / finalTokens[1].backingUnit == 2); // Original ratio maintained
      },
    );

    test(
      "handles edge cases in supply management",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        // Test 1: Cannot decrease supply when at zero
        switch (ops.processSupplyDecrease(100)) {
          case (#err(#InvalidSupplyChange({ currentSupply; requestedChange; reason }))) {
            assert currentSupply == 0;
            assert requestedChange == 100;
            assert reason == "Cannot decrease supply by more than current supply";
          };
          case _ { assert false };
        };

        // Mint tokens for testing
        va.mint(caller, tokenA, 400);
        va.mint(caller, tokenB, 200);

        // Test 2: Issue some tokens to test with
        assert (ops.processIssue(caller, 200) == #ok());

        // Verify initial ratios
        let initialTokens = store.getBackingTokens();
        assert initialTokens[0].backingUnit == 100;
        assert initialTokens[1].backingUnit == 50;

        // Test 3: Cannot decrease by non-aligned amount
        switch (ops.processSupplyDecrease(150)) {
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 150;
          };
          case _ { assert false };
        };

        // Test 4: Large supply increase
        assert (ops.processSupplyIncrease(1000) == #ok());
        let afterIncreaseTokens = store.getBackingTokens();
        assert afterIncreaseTokens[0].backingUnit == 16; // 200/12 = 16
        assert afterIncreaseTokens[1].backingUnit == 8; // 100/12 = 8

        // Verify ratios maintained
        assert (afterIncreaseTokens[0].backingUnit / afterIncreaseTokens[1].backingUnit == 2);

        // Verify system balances remained consistent
        assert (va.getBalance(systemAccount, tokenA) == 200);
        assert (va.getBalance(systemAccount, tokenB) == 100);
      },
    );
  },
);
