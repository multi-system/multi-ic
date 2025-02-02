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
    let caller = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let tokenA = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    let initState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
    var virtualAccounts : VirtualAccounts.VirtualAccountManager = VirtualAccounts.VirtualAccountManager(initState);
    var backingImpl : BackingOperations.BackingOperationsImpl = BackingOperations.BackingOperationsImpl(virtualAccounts);

    let setup = func() {
      let freshState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();
      virtualAccounts := VirtualAccounts.VirtualAccountManager(freshState);
      backingImpl := BackingOperations.BackingOperationsImpl(virtualAccounts);
    };

    test(
      "handles issue with sufficient virtual balance",
      func() {
        setup();
        virtualAccounts.mint(caller, tokenA, 200);
        virtualAccounts.mint(caller, tokenB, 100);

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
            Debug.print("Issue failed: " # e);
            assert false;
          };
          case (#ok(result)) {
            assert (result.totalSupply == amount);
            assert (result.amount == amount);
            assert (virtualAccounts.getBalance(caller, tokenA) == 100);
            assert (virtualAccounts.getBalance(caller, tokenB) == 50);
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
        virtualAccounts.mint(caller, tokenA, 50);
        virtualAccounts.mint(caller, tokenB, 100);

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
            assert false;
          };
        };

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
        let amount = 150;

        switch (backingImpl.processIssue(caller, systemAccount, amount, supplyUnit, 0, backingTokens)) {
          case (#err(e)) {
            assert (e == "Amount must be multiple of supply unit");
          };
          case (#ok(_)) {
            assert false;
          };
        };
      },
    );

    test(
      "handles redeem with sufficient system balance",
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
        let totalSupply = 200;
        let amount = 100;

        switch (backingImpl.processRedeem(caller, systemAccount, amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            Debug.print("Redeem failed: " # e);
            assert false;
          };
          case (#ok(result)) {
            assert (result.totalSupply == totalSupply - amount);
            assert (result.amount == amount);
            assert (virtualAccounts.getBalance(systemAccount, tokenA) == 100);
            assert (virtualAccounts.getBalance(systemAccount, tokenB) == 50);
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
        let totalSupply = 200;
        let amount = 300;

        switch (backingImpl.processRedeem(caller, systemAccount, amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            assert (e == "Cannot redeem more units than eta (M/u)");
          };
          case (#ok(_)) {
            assert false;
          };
        };

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
        virtualAccounts.mint(systemAccount, tokenA, 50);
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
            assert false;
          };
        };
      },
    );

    test(
      "handles backing increase with valid amount",
      func() {
        setup();

        let backingTokens : [var Types.BackingPair] = [
          var {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 300;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 150;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 100;

        switch (backingImpl.processBackingIncrease(amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            Debug.print("Backing increase failed: " # e);
            assert false;
          };
          case (#ok(result)) {
            assert (result.totalSupply == 300);
            assert (result.amount == amount);
          };
        };
      },
    );

    test(
      "fails backing increase when amount not aligned with supply unit",
      func() {
        setup();

        let backingTokens : [var Types.BackingPair] = [
          var {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 200;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 150;

        switch (backingImpl.processBackingIncrease(amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            assert (e == "Amount must be multiple of supply unit");
          };
          case (#ok(_)) {
            assert false;
          };
        };
      },
    );

    test(
      "handles backing decrease with valid amount",
      func() {
        setup();

        let backingTokens : [var Types.BackingPair] = [
          var {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 100;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 50;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 100;

        switch (backingImpl.processBackingDecrease(amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            Debug.print("Backing decrease failed: " # e);
            assert false;
          };
          case (#ok(result)) {
            assert (result.totalSupply == 100);
            assert (result.amount == amount);
          };
        };
      },
    );

    test(
      "fails backing decrease when supply would become invalid",
      func() {
        setup();

        let backingTokens : [var Types.BackingPair] = [
          var {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 200;
          },
        ];

        let supplyUnit = 100;
        let totalSupply = 200;
        let amount = 150;

        switch (backingImpl.processBackingDecrease(amount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) {
            assert (e == "Amount must be multiple of supply unit");
          };
          case (#ok(_)) {
            assert false;
          };
        };
      },
    );
  },
);
