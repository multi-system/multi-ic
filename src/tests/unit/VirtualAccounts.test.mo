import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/Types";
import TransferTypes "../../multi_backend/types/TransferTypes";
import AccountTypes "../../multi_backend/types/AccountTypes";
import VirtualAccounts "../../multi_backend/custodial/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

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
        manager.mint(bob, tokenA, 10);
        assert (manager.hasInsufficientBalance(bob, tokenA, 20));
        assert (not manager.hasInsufficientBalance(bob, tokenA, 5));
      },
    );

    test(
      "validates zero amount correctly",
      func() {
        setup();
        assert (not manager.isValidAmount(0));
        assert (manager.isValidAmount(1));
        assert (manager.isValidAmount(100));
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
        assert (manager.getBalance(alice, nonExistentToken) == 0);
      },
    );

    // Basic operation tests
    test(
      "handles simple transfer",
      func() {
        setup();
        manager.mint(alice, tokenA, 100);

        assert (manager.getBalance(alice, tokenA) == 100);
        assert (manager.getBalance(bob, tokenA) == 0);

        let transferArgs : TransferTypes.TransferArgs = {
          from = alice;
          to = bob;
          token = tokenA;
          amount = 40;
        };
        manager.transfer(transferArgs);

        assert (manager.getBalance(alice, tokenA) == 60);
        assert (manager.getBalance(bob, tokenA) == 40);
      },
    );

    test(
      "can get all balances",
      func() {
        setup();
        manager.mint(alice, tokenA, 200);
        manager.mint(alice, tokenB, 300);

        let balances = manager.getAllBalances(alice);
        assert (balances.size() == 2);

        let hasTokenA = Array.find<(Types.Token, Nat)>(
          balances,
          func((token, amount)) = Principal.equal(token, tokenA) and amount == 200,
        );
        let hasTokenB = Array.find<(Types.Token, Nat)>(
          balances,
          func((token, amount)) = Principal.equal(token, tokenB) and amount == 300,
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
        manager.mint(alice, tokenA, 100);
        manager.burn(alice, tokenA, 100);
        assert (manager.getBalance(alice, tokenA) == 0);
      },
    );

    test(
      "handles maximum values",
      func() {
        setup();
        let maxNat : Nat = 0xFFFFFFFFFFFFFFFF;
        manager.mint(alice, tokenA, maxNat);
        assert (manager.getBalance(alice, tokenA) == maxNat);
      },
    );

    // Complex operation tests
    test(
      "maintains correct balances after multiple token operations",
      func() {
        setup();
        let tokenC : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

        // Setup initial state
        manager.mint(alice, tokenA, 100);
        manager.mint(alice, tokenB, 50);
        manager.mint(bob, tokenC, 75);

        // Perform multiple operations
        let transferArgs : TransferTypes.TransferArgs = {
          from = alice;
          to = bob;
          token = tokenA;
          amount = 30;
        };
        manager.transfer(transferArgs);

        manager.mint(bob, tokenB, 25);

        // Verify multiple token balances
        assert (manager.getBalance(alice, tokenA) == 70);
        assert (manager.getBalance(alice, tokenB) == 50);
        assert (manager.getBalance(bob, tokenA) == 30);
        assert (manager.getBalance(bob, tokenB) == 25);
        assert (manager.getBalance(bob, tokenC) == 75);

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
        manager.mint(alice, tokenA, 100);
        manager.mint(bob, tokenB, 100);

        // Create circular transfer pattern
        manager.transfer({
          from = alice;
          to = bob;
          token = tokenA;
          amount = 50;
        });

        manager.transfer({
          from = bob;
          to = charlie;
          token = tokenA;
          amount = 20;
        });

        manager.transfer({
          from = bob;
          to = charlie;
          token = tokenB;
          amount = 40;
        });

        // Verify final state
        assert (manager.getBalance(alice, tokenA) == 50);
        assert (manager.getBalance(bob, tokenA) == 30);
        assert (manager.getBalance(bob, tokenB) == 60);
        assert (manager.getBalance(charlie, tokenA) == 20);
        assert (manager.getBalance(charlie, tokenB) == 40);
      },
    );
  },
);
