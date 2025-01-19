import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

suite(
  "Virtual Accounts",
  func() {
    // Using valid principal IDs
    let alice = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let bob = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let initState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
    var manager : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager(initState);

    // Reset state before each test
    let setup = func() {
      let freshState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
      manager := VirtualAccounts.VirtualAccountManager(freshState);
    };

    // Validation tests
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

    // Operation tests
    test(
      "handles simple transfer",
      func() {
        setup();
        manager.mint(alice, tokenA, 100);

        assert (manager.getBalance(alice, tokenA) == 100);
        assert (manager.getBalance(bob, tokenA) == 0);

        manager.transfer({
          from = alice;
          to = bob;
          token = tokenA;
          amount = 40;
        });

        assert (manager.getBalance(alice, tokenA) == 60);
        assert (manager.getBalance(bob, tokenA) == 40);
      },
    );

    test(
      "can get all balances",
      func() {
        setup();
        manager.mint(alice, tokenA, 200);
        let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
        manager.mint(alice, tokenB, 300);

        let balances = manager.getAllBalances(alice);
        assert (balances.size() == 2);

        let hasTokenA = Array.find<(Principal, Nat)>(
          balances,
          func((token, amount)) = Principal.equal(token, tokenA) and amount == 200,
        );
        let hasTokenB = Array.find<(Principal, Nat)>(
          balances,
          func((token, amount)) = Principal.equal(token, tokenB) and amount == 300,
        );

        assert (Option.isSome(hasTokenA));
        assert (Option.isSome(hasTokenB));
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

    test(
      "handles multiple token operations",
      func() {
        setup();
        let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
        manager.mint(alice, tokenA, 100);
        manager.mint(alice, tokenB, 200);
        manager.mint(bob, tokenA, 50);

        manager.transfer({
          from = alice;
          to = bob;
          token = tokenA;
          amount = 30;
        });

        manager.burn(alice, tokenB, 100);
        manager.mint(bob, tokenB, 75);

        assert (manager.getBalance(alice, tokenA) == 70);
        assert (manager.getBalance(alice, tokenB) == 100);
        assert (manager.getBalance(bob, tokenA) == 80);
        assert (manager.getBalance(bob, tokenB) == 75);
      },
    );
  },
);
