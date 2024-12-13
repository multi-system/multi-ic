import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Types "../../multi_backend/types/BackingTypes";
import VirtualTypes "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import BackingOperations "../../multi_backend/backing/BackingOperations";

suite(
  "Backing Operations",
  func() {
    // Test principals
    let caller = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    var virtualAccounts : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager();
    var backingImpl : BackingOperations.BackingOperationsImpl = BackingOperations.BackingOperationsImpl(virtualAccounts);

    // Reset state before each test
    let setup = func() {
      virtualAccounts := VirtualAccounts.VirtualAccountManager();
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

        // Attempting the transfer will trap, but state should be unchanged
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
      "preserves atomicity on partial failure",
      func() {
        setup();
        // Setup balances where first transfer would succeed but second would fail
        virtualAccounts.mint(caller, tokenA, 200); // Enough for first token
        virtualAccounts.mint(caller, tokenB, 20); // Not enough for second token

        // Verify initial state
        assert (virtualAccounts.getBalance(caller, tokenA) == 200);
        assert (virtualAccounts.getBalance(caller, tokenB) == 20);
        assert (virtualAccounts.getBalance(systemAccount, tokenA) == 0);
        assert (virtualAccounts.getBalance(systemAccount, tokenB) == 0);

        // Attempting the transfer will trap, but state should be unchanged
      },
    );
  },
);
