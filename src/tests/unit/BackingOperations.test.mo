import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Types "../../multi_backend/types/BackingTypes";
import VirtualTypes "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import BackingOperations "../../multi_backend/backing/BackingOperations";
import BackingStore "../../multi_backend/backing/BackingStore";
import Array "mo:base/Array";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

suite(
  "Backing Operations",
  func() {
    let caller = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    let initState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
    var virtualAccounts : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager(initState);

    // Initial backing state
    let initialBackingState : Types.BackingState = {
      var hasInitialized = false;
      var config = {
        supplyUnit = 0;
        totalSupply = 0;
        backingPairs = [];
      };
    };

    var backingStore : BackingStore.BackingStore = BackingStore.BackingStore(initialBackingState);
    var backingImpl : BackingOperations.BackingOperationsImpl = BackingOperations.BackingOperationsImpl(
      backingStore,
      virtualAccounts,
      systemAccount,
    );

    let setup = func() {
      let freshState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
      virtualAccounts := VirtualAccounts.VirtualAccountManager(freshState);

      // Reset backing state
      let freshBackingState : Types.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 0;
          totalSupply = 0;
          backingPairs = [];
        };
      };

      backingStore := BackingStore.BackingStore(freshBackingState);
      backingImpl := BackingOperations.BackingOperationsImpl(
        backingStore,
        virtualAccounts,
        systemAccount,
      );

      // Initialize backing store with test configuration
      let initialTokens : [Types.BackingPair] = [
        {
          tokenInfo = { canisterId = tokenA };
          backingUnit = 100;
        },
        {
          tokenInfo = { canisterId = tokenB };
          backingUnit = 50;
        },
      ];

      assert (backingStore.initialize(100, initialTokens) == #ok(()));
    };

    test(
      "handles issue with sufficient virtual balance",
      func() {
        setup();
        virtualAccounts.mint(caller, tokenA, 200);
        virtualAccounts.mint(caller, tokenB, 100);

        switch (backingImpl.processIssue(caller, 100)) {
          case (#err(e)) {
            Debug.print("Issue failed: " # e);
            assert false;
          };
          case (#ok()) {
            assert (virtualAccounts.getBalance(caller, tokenA) == 100);
            assert (virtualAccounts.getBalance(caller, tokenB) == 50);
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 100);
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 50);
            assert (backingStore.getTotalSupply() == 100);
          };
        };
      },
    );

    test(
      "fails issue with insufficient virtual balance",
      func() {
        setup();
        virtualAccounts.mint(caller, tokenA, 50);
        virtualAccounts.mint(caller, tokenB, 100);

        assert (virtualAccounts.getBalance(caller, tokenA) == 50);
        assert (virtualAccounts.getBalance(caller, tokenB) == 100);
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 0);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 0);

        switch (backingImpl.processIssue(caller, 100)) {
          case (#err(e)) {
            assert (e == "Insufficient balance for token " # Principal.toText(tokenA));
          };
          case (#ok()) {
            assert false;
          };
        };

        assert (virtualAccounts.getBalance(caller, tokenA) == 50);
        assert (virtualAccounts.getBalance(caller, tokenB) == 100);
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 0);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 0);
        assert (backingStore.getTotalSupply() == 0);
      },
    );

    test(
      "fails when amount not aligned with supply unit",
      func() {
        setup();
        virtualAccounts.mint(caller, tokenA, 200);
        virtualAccounts.mint(caller, tokenB, 100);

        switch (backingImpl.processIssue(caller, 150)) {
          case (#err(e)) {
            assert (e == "Amount must be multiple of supply unit");
          };
          case (#ok()) {
            assert false;
          };
        };
      },
    );

    test(
      "handles redeem with sufficient system balance",
      func() {
        setup();

        // First issue some tokens to create system balance
        virtualAccounts.mint(caller, tokenA, 200);
        virtualAccounts.mint(caller, tokenB, 100);
        assert (backingImpl.processIssue(caller, 200) == #ok());

        // Now try to redeem
        switch (backingImpl.processRedeem(caller, 100)) {
          case (#err(e)) {
            Debug.print("Redeem failed: " # e);
            assert false;
          };
          case (#ok()) {
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 100);
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 50);
            assert (virtualAccounts.getBalance(caller, tokenA) == 100);
            assert (virtualAccounts.getBalance(caller, tokenB) == 50);
            assert (backingStore.getTotalSupply() == 100);
          };
        };
      },
    );

    test(
      "correctly adjusts backing ratios after supply changes",
      func() {
        setup();

        // Initial state setup with proper backing
        virtualAccounts.mint(caller, tokenA, 400); // Initial reserve for Token A
        virtualAccounts.mint(caller, tokenB, 200); // Initial reserve for Token B

        // 1. First issue sets up our reserve quantities
        assert (backingImpl.processIssue(caller, 200) == #ok());

        // 2. Process supply increase (which decreases backing ratios since tokens are spread thinner)
        switch (backingImpl.processSupplyIncrease(400)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = backingStore.getBackingTokens();
            // Verify new backing units decreased due to higher supply
            assert backingTokens[0].backingUnit == 33; // 200/6 = 33 (decreased from 100)
            assert backingTokens[1].backingUnit == 16; // 100/6 = 16 (decreased from 50)
          };
        };

        // 3. Issue with new lower ratios
        assert (backingImpl.processIssue(caller, 100) == #ok());

        // Verify transfers used new lower ratios
        assert virtualAccounts.getBalance(caller, tokenA) == 167; // 200 - 33
        assert virtualAccounts.getBalance(caller, tokenB) == 84; // 100 - 16
        assert virtualAccounts.getBalance(systemAccount, tokenA) == 233; // 200 + 33
        assert virtualAccounts.getBalance(systemAccount, tokenB) == 116; // 100 + 16

        // 4. Process supply decrease (which increases backing ratios)
        switch (backingImpl.processSupplyDecrease(300)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = backingStore.getBackingTokens();
            // Verify new backing units increased due to lower supply
            assert backingTokens[0].backingUnit == 58; // 233/4 = 58 (increased from 33)
            assert backingTokens[1].backingUnit == 29; // 116/4 = 29 (increased from 16)
          };
        };

        // 5. Redeem with new higher ratios
        assert (backingImpl.processRedeem(caller, 100) == #ok());

        // Verify transfers used new higher ratios
        assert virtualAccounts.getBalance(caller, tokenA) == 225; // 167 + 58
        assert virtualAccounts.getBalance(caller, tokenB) == 113; // 84 + 29
        assert virtualAccounts.getBalance(systemAccount, tokenA) == 175; // 233 - 58
        assert virtualAccounts.getBalance(systemAccount, tokenB) == 87; // 116 - 29
      },
    );

    test(
      "handles supply management edge cases correctly",
      func() {
        setup();
        virtualAccounts.mint(caller, tokenA, 500);
        virtualAccounts.mint(caller, tokenB, 250);

        // Setup initial state
        assert (backingImpl.processIssue(caller, 100) == #ok());

        // Test 1: Cannot decrease supply below supply unit
        switch (backingImpl.processSupplyDecrease(100)) {
          case (#err(e)) {
            assert (e == "Total supply cannot be less than supply unit");
          };
          case (#ok()) { assert false };
        };

        // Test 2: Increase by large amount to test ratio precision
        switch (backingImpl.processSupplyIncrease(900)) {
          case (#err(_)) { assert false };
          case (#ok()) {
            let backingTokens = backingStore.getBackingTokens();
            // With 1000 total supply, ratios should be divided by 10
            assert backingTokens[0].backingUnit == 10; // 100/10
            assert backingTokens[1].backingUnit == 5; // 50/10
          };
        };

        // Test 3: Multiple operations in sequence
        assert (backingImpl.processIssue(caller, 100) == #ok());

        // First decrease
        switch (backingImpl.processSupplyDecrease(200)) {
          case (#err(_)) { assert false };
          case (#ok()) {
            let backingTokens = backingStore.getBackingTokens();
            // 900 total supply, verify ratios adjusted up
            assert backingTokens[0].backingUnit == 12; // (100+10)/9
            assert backingTokens[1].backingUnit == 6; // (50+5)/9
          };
        };

        // Then increase again
        switch (backingImpl.processSupplyIncrease(300)) {
          case (#err(_)) { assert false };
          case (#ok()) {
            let backingTokens = backingStore.getBackingTokens();
            // Total supply is 1200 (eta=12), verify ratios adjusted
            assert backingTokens[0].backingUnit == 9; // 110 / 12 = 9
            assert backingTokens[1].backingUnit == 4; // 55 / 12 = 4

            // Verify system account balances stayed consistent
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 110);
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 55);
          };
        };
      },
    );
  },
);
