import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Types "../../multi_backend/types/BackingTypes";
import VirtualTypes "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import BackingOperations "../../multi_backend/backing/BackingOperations";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

suite(
  "Backing Operations",
  func() {
    // Test principals
    let caller = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    let initState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
    var virtualAccounts : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager(initState);
    var backingImpl : BackingOperations.BackingOperationsImpl = BackingOperations.BackingOperationsImpl(virtualAccounts);

    // Reset state before each test
    let setup = func() {
      let freshState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
      virtualAccounts := VirtualAccounts.VirtualAccountManager(freshState);
      backingImpl := BackingOperations.BackingOperationsImpl(virtualAccounts);
    };

    test(
      "handles issue with sufficient virtual balance",
      func() {
        setup();
        // Setup virtual balances
        virtualAccounts.mint(caller, tokenA, 200);
        virtualAccounts.mint(caller, tokenB, 100);

        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100; // 2:1 ratio
            reserveQuantity = 0;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50; // 1:1 ratio
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let amount = 100; // Should require 100 of tokenA and 50 of tokenB

        switch (backingImpl.processIssue(caller, systemAccount, amount, supplyUnit, 0, backingTokens)) {
          case (#err(e)) {
            Debug.print("Issue failed: " # e);
            assert (false);
          };
          case (#ok(result)) {
            // Check the total supply was updated
            assert (result.totalSupply == amount);
            assert (result.amount == amount);

            // Check that virtual balances were transferred correctly
            assert (virtualAccounts.getBalance(caller, tokenA) == 100); // 200 - 100
            assert (virtualAccounts.getBalance(caller, tokenB) == 50); // 100 - 50
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 100);
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 50);
          };
        };
      },
    );

    test(
      "fails issue with insufficient virtual balance",
      func() {
        setup();
        // Setup insufficient balances
        virtualAccounts.mint(caller, tokenA, 50); // Not enough
        virtualAccounts.mint(caller, tokenB, 100); // Enough

        // Verify initial state
        assert (virtualAccounts.getBalance(caller, tokenA) == 50);
        assert (virtualAccounts.getBalance(caller, tokenB) == 100);
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 0);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 0);

        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 0;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let amount = 100;

        switch (backingImpl.processIssue(caller, systemAccount, amount, supplyUnit, 0, backingTokens)) {
          case (#err(e)) {
            assert (e == "Insufficient balance for token " # Principal.toText(tokenA));
          };
          case (#ok(_)) {
            assert (false);
          };
        };

        // Verify state remains unchanged
        assert (virtualAccounts.getBalance(caller, tokenA) == 50);
        assert (virtualAccounts.getBalance(caller, tokenB) == 100);
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 0);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 0);
      },
    );

    test(
      "fails when amount not aligned with supply unit",
      func() {
        setup();
        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let amount = 150; // Not aligned with supply unit

        switch (backingImpl.processIssue(caller, systemAccount, amount, supplyUnit, 0, backingTokens)) {
          case (#err(e)) {
            assert (e == "Amount must be multiple of supply unit");
          };
          case (#ok(_)) {
            assert (false);
          };
        };
      },
    );

    test(
      "handles redeem with sufficient system balance",
      func() {
        setup();
        // Setup virtual balances for system account
        virtualAccounts.mint(systemAccount, tokenA, 200);
        virtualAccounts.mint(systemAccount, tokenB, 100);

        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100; // 2:1 ratio
            reserveQuantity = 0;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50; // 1:1 ratio
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 100; // Should transfer 100 of tokenA and 50 of tokenB

        switch (backingImpl.processRedeem(caller, systemAccount, amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            Debug.print("Redeem failed: " # e);
            assert (false);
          };
          case (#ok(result)) {
            // Check the total supply was updated
            assert (result.totalSupply == totalSupply - amount);
            assert (result.amount == amount);

            // Check that virtual balances were transferred correctly
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 100); // 200 - 100
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 50); // 100 - 50
            assert (virtualAccounts.getBalance(caller, tokenA) == 100);
            assert (virtualAccounts.getBalance(caller, tokenB) == 50);
          };
        };
      },
    );

    test(
      "fails redeem when amount exceeds eta",
      func() {
        setup();
        virtualAccounts.mint(systemAccount, tokenA, 200);
        virtualAccounts.mint(systemAccount, tokenB, 100);

        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 0;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200; // eta = 2
        let amount = 300; // Requesting 3 units > eta

        switch (backingImpl.processRedeem(caller, systemAccount, amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            assert (e == "Cannot redeem more units than eta (M/u)");
          };
          case (#ok(_)) {
            assert (false);
          };
        };

        // Verify state remains unchanged
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 200);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 100);
        assert (virtualAccounts.getBalance(caller, tokenA) == 0);
        assert (virtualAccounts.getBalance(caller, tokenB) == 0);
      },
    );

    test(
      "fails redeem with insufficient system balance",
      func() {
        setup();
        // Setup insufficient system balances
        virtualAccounts.mint(systemAccount, tokenA, 50); // Not enough
        virtualAccounts.mint(systemAccount, tokenB, 100);

        let backingTokens : [Types.BackingPair] = [
          {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 0;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 0;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 100;

        switch (backingImpl.processRedeem(caller, systemAccount, amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            assert (e == "Insufficient system balance for token " # Principal.toText(tokenA));
          };
          case (#ok(_)) {
            assert (false);
          };
        };
      },
    );
  },
);
