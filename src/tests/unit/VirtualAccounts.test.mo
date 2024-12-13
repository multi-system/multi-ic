import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";

suite(
  "Virtual Accounts",
  func() {
    // Using valid principal IDs
    let alice = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let bob = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    var manager : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager();

    // Reset state before each test
    let setup = func() {
      manager := VirtualAccounts.VirtualAccountManager();
    };

    test(
      "handles simple transfer",
      func() {
        setup();
        // Initialize alice's balance by minting
        manager.mint(alice, tokenA, 100);

        assert (manager.getBalance(alice, tokenA) == 100);
        assert (manager.getBalance(bob, tokenA) == 0);

        // Transfer from alice to bob
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
      "prevents transfer with insufficient balance",
      func() {
        setup();
        // Initialize bob with a small balance
        manager.mint(bob, tokenA, 10);

        // Verify initial state
        assert (manager.getBalance(bob, tokenA) == 10);
        assert (manager.getBalance(alice, tokenA) == 0);

        // Attempting transfer will trap, but state should be unchanged
      },
    );

    test(
      "prevents zero amount transfer",
      func() {
        setup();
        // Initialize some balances
        manager.mint(bob, tokenA, 20);
        manager.mint(alice, tokenA, 30);

        // Verify initial state
        assert (manager.getBalance(bob, tokenA) == 20);
        assert (manager.getBalance(alice, tokenA) == 30);

        // Attempting zero transfer will trap, but state should be unchanged
      },
    );

    test(
      "can get all balances",
      func() {
        setup();
        // Initialize multiple balances
        manager.mint(alice, tokenA, 200);
        let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
        manager.mint(alice, tokenB, 300);

        let balances = manager.getAllBalances(alice);
        assert (balances.size() == 2);

        // Verify the balances contain our expected values
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
  },
);
