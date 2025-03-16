import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import TransferTypes "../../../multi_backend/types/TransferTypes";
import AccountTypes "../../../multi_backend/types/AccountTypes";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AmountOperations "../../../multi_backend/financial/AmountOperations";

suite(
  "Virtual Accounts",
  func() {
    // Using valid principal IDs
    let alice : Types.Account = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let bob : Types.Account = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
    let initState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();
    var manager : VirtualAccounts.VirtualAccounts = VirtualAccounts.VirtualAccounts(initState);

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    // Reset state before each test
    let setup = func() {
      let freshState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();
      manager := VirtualAccounts.VirtualAccounts(freshState);
    };

    // Validation function tests
    test(
      "validates multiple principals correctly",
      func() {
        setup();
        let validPrincipals = [alice, bob, tokenA];
        assert (manager.hasValidPrincipals(validPrincipals));
      },
    );

    test(
      "validates insufficient balance correctly",
      func() {
        setup();
        manager.mint(bob, amount(tokenA, 10));
        assert (manager.hasInsufficientBalance(bob, amount(tokenA, 20)));
        assert (not manager.hasInsufficientBalance(bob, amount(tokenA, 5)));
      },
    );

    test(
      "validates zero amount correctly",
      func() {
        setup();
        assert (not manager.isValidAmount(amount(tokenA, 0)));
        assert (manager.isValidAmount(amount(tokenA, 1)));
        assert (manager.isValidAmount(amount(tokenA, 100)));
      },
    );

    test(
      "validates self transfers correctly",
      func() {
        setup();
        assert (manager.isSelfTransfer(alice, alice));
        assert (not manager.isSelfTransfer(alice, bob));
      },
    );

    test(
      "handles non-existent token balances correctly",
      func() {
        setup();
        let nonExistentToken : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
        let balance = manager.getBalance(alice, nonExistentToken);
        assert (balance.value == 0);
      },
    );

    // Basic operation tests
    test(
      "handles simple transfer",
      func() {
        setup();
        manager.mint(alice, amount(tokenA, 100));

        assert (manager.getBalance(alice, tokenA).value == 100);
        assert (manager.getBalance(bob, tokenA).value == 0);

        let transferArgs : TransferTypes.TransferArgs = {
          from = alice;
          to = bob;
          amount = amount(tokenA, 40);
        };
        manager.transfer(transferArgs);

        assert (manager.getBalance(alice, tokenA).value == 60);
        assert (manager.getBalance(bob, tokenA).value == 40);
      },
    );

    test(
      "can get all balances",
      func() {
        setup();
        manager.mint(alice, amount(tokenA, 200));
        manager.mint(alice, amount(tokenB, 300));

        let balances = manager.getAllBalances(alice);
        assert (balances.size() == 2);

        let hasTokenA = Array.find<Types.Amount>(
          balances,
          func(amt) = Principal.equal(amt.token, tokenA) and amt.value == 200,
        );
        let hasTokenB = Array.find<Types.Amount>(
          balances,
          func(amt) = Principal.equal(amt.token, tokenB) and amt.value == 300,
        );

        assert (Option.isSome(hasTokenA));
        assert (Option.isSome(hasTokenB));
      },
    );

    test(
      "handles getAllBalances for empty account",
      func() {
        setup();
        let emptyAccBalances = manager.getAllBalances(alice);
        assert (emptyAccBalances.size() == 0);
      },
    );

    test(
      "can burn exact balance",
      func() {
        setup();
        manager.mint(alice, amount(tokenA, 100));
        manager.burn(alice, amount(tokenA, 100));
        assert (manager.getBalance(alice, tokenA).value == 0);
      },
    );

    test(
      "handles maximum values",
      func() {
        setup();
        let maxNat : Nat = 0xFFFFFFFFFFFFFFFF;
        manager.mint(alice, amount(tokenA, maxNat));
        assert (manager.getBalance(alice, tokenA).value == maxNat);
      },
    );

    test(
      "calculates total balance correctly across multiple accounts",
      func() {
        setup();
        // Initially no balances
        assert (manager.getTotalBalance(tokenA).value == 0);

        // Add some balances across different accounts
        manager.mint(alice, amount(tokenA, 100));
        manager.mint(bob, amount(tokenA, 150));

        // Check total balance
        assert (manager.getTotalBalance(tokenA).value == 250);

        // Add more to an existing account
        manager.mint(alice, amount(tokenA, 50));
        assert (manager.getTotalBalance(tokenA).value == 300);

        // Transfer between accounts should not change total
        let transferArgs : TransferTypes.TransferArgs = {
          from = alice;
          to = bob;
          amount = amount(tokenA, 75);
        };
        manager.transfer(transferArgs);
        assert (manager.getTotalBalance(tokenA).value == 300);

        // Burn some tokens and verify total decreases
        manager.burn(bob, amount(tokenA, 100));
        assert (manager.getTotalBalance(tokenA).value == 200);

        // Different token should have different total
        assert (manager.getTotalBalance(tokenB).value == 0);
        manager.mint(alice, amount(tokenB, 500));
        assert (manager.getTotalBalance(tokenB).value == 500);
        assert (manager.getTotalBalance(tokenA).value == 200);
      },
    );

    // Complex operation tests
    test(
      "maintains correct balances after multiple token operations",
      func() {
        setup();
        let tokenC : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

        // Setup initial state
        manager.mint(alice, amount(tokenA, 100));
        manager.mint(alice, amount(tokenB, 50));
        manager.mint(bob, amount(tokenC, 75));

        // Perform multiple operations
        let transferArgs : TransferTypes.TransferArgs = {
          from = alice;
          to = bob;
          amount = amount(tokenA, 30);
        };
        manager.transfer(transferArgs);

        manager.mint(bob, amount(tokenB, 25));

        // Verify multiple token balances
        assert (manager.getBalance(alice, tokenA).value == 70);
        assert (manager.getBalance(alice, tokenB).value == 50);
        assert (manager.getBalance(bob, tokenA).value == 30);
        assert (manager.getBalance(bob, tokenB).value == 25);
        assert (manager.getBalance(bob, tokenC).value == 75);

        // Verify getAllBalances consistency
        let aliceBalances = manager.getAllBalances(alice);
        let bobBalances = manager.getAllBalances(bob);

        assert (aliceBalances.size() == 2);
        assert (bobBalances.size() == 3);
      },
    );

    test(
      "maintains state consistency in complex transfer patterns",
      func() {
        setup();
        let charlie : Types.Account = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");

        // Initial mints
        manager.mint(alice, amount(tokenA, 100));
        manager.mint(bob, amount(tokenB, 100));

        // Create circular transfer pattern
        manager.transfer({
          from = alice;
          to = bob;
          amount = amount(tokenA, 50);
        });

        manager.transfer({
          from = bob;
          to = charlie;
          amount = amount(tokenA, 20);
        });

        manager.transfer({
          from = bob;
          to = charlie;
          amount = amount(tokenB, 40);
        });

        // Verify final state
        assert (manager.getBalance(alice, tokenA).value == 50);
        assert (manager.getBalance(bob, tokenA).value == 30);
        assert (manager.getBalance(bob, tokenB).value == 60);
        assert (manager.getBalance(charlie, tokenA).value == 20);
        assert (manager.getBalance(charlie, tokenB).value == 40);
      },
    );
  },
);
