import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/Types";
import AccountTypes "../../multi_backend/types/AccountTypes";
import VirtualAccounts "../../multi_backend/custodial/VirtualAccounts";
import VirtualAccountBridge "../../multi_backend/custodial/VirtualAccountBridge";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

suite(
  "Virtual Account Bridge",
  func() {
    // Test principals
    let user : Types.Account = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let user2 : Types.Account = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    // Setup helper
    let setup = func() : (VirtualAccounts.VirtualAccounts, VirtualAccounts.VirtualAccounts) {
      let sourceState = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
      let destState = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();

      let source = VirtualAccounts.VirtualAccounts(sourceState);
      let destination = VirtualAccounts.VirtualAccounts(destState);

      // Set up initial balances
      source.mint(user, amount(tokenA, 100));
      source.mint(user, amount(tokenB, 200));
      source.mint(user2, amount(tokenA, 150));

      (source, destination);
    };

    test(
      "transfer moves tokens between accounts correctly",
      func() {
        let (source, destination) = setup();

        // Perform transfers for different tokens and users
        VirtualAccountBridge.transfer(source, destination, user, amount(tokenA, 50));
        VirtualAccountBridge.transfer(source, destination, user, amount(tokenB, 75));
        VirtualAccountBridge.transfer(source, destination, user2, amount(tokenA, 100));

        // Verify balances in source
        assert (source.getBalance(user, tokenA).value == 50);
        assert (source.getBalance(user, tokenB).value == 125);
        assert (source.getBalance(user2, tokenA).value == 50);

        // Verify balances in destination
        assert (destination.getBalance(user, tokenA).value == 50);
        assert (destination.getBalance(user, tokenB).value == 75);
        assert (destination.getBalance(user2, tokenA).value == 100);

        // Verify total balances
        assert (source.getTotalBalance(tokenA).value == 100); // 50 + 50
        assert (destination.getTotalBalance(tokenA).value == 150); // 50 + 100
        assert (source.getTotalBalance(tokenB).value == 125);
        assert (destination.getTotalBalance(tokenB).value == 75);
      },
    );

    test(
      "transfer exact balance works correctly",
      func() {
        let (source, destination) = setup();

        // Transfer entire balance of tokenA from user
        VirtualAccountBridge.transfer(source, destination, user, amount(tokenA, 100));

        // Verify balances
        assert (source.getBalance(user, tokenA).value == 0);
        assert (destination.getBalance(user, tokenA).value == 100);

        // TokenB should remain untouched
        assert (source.getBalance(user, tokenB).value == 200);
      },
    );
  },
);
