import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Types "../../multi_backend/types/BackingTypes";
import VirtualTypes "../../multi_backend/types/VirtualTypes";
import VirtualAccounts "../../multi_backend/ledger/VirtualAccounts";
import BackingOperations "../../multi_backend/backing/BackingOperations";
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

    test(
      "correctly adjusts backing ratios after supply changes",
      func() {
        setup();

        // Initial state setup
        virtualAccounts.mint(caller, tokenA, 400);
        virtualAccounts.mint(caller, tokenB, 200);
        virtualAccounts.mint(systemAccount, tokenA, 200);
        virtualAccounts.mint(systemAccount, tokenB, 100);

        let backingTokens : [var Types.BackingPair] = [
          var {
            tokenInfo = { canisterId = tokenA };
            backingUnit = 100;
            reserveQuantity = 200;
          },
          {
            tokenInfo = { canisterId = tokenB };
            backingUnit = 50;
            reserveQuantity = 100;
          },
        ];

        let supplyUnit = 100;
        var totalSupply = 200;

        // 1. Supply increase: 2 -> 6 supply units
        let increaseAmount = 400;
        switch (backingImpl.processBackingIncrease(increaseAmount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) { assert false };
          case (#ok(result)) {
            totalSupply := result.totalSupply;

            // Verify new backing units
            assert backingTokens[0].backingUnit == 33; // 200/6 = 33
            assert backingTokens[1].backingUnit == 16; // 100/6 = 16
          };
        };

        // 2. Issue with new ratios (33/16)
        let issueAmount = 100;
        let frozenTokens = Array.freeze(backingTokens);
        switch (backingImpl.processIssue(caller, systemAccount, issueAmount, supplyUnit, totalSupply, frozenTokens)) {
          case (#err(e)) { assert false };
          case (#ok(result)) {
            totalSupply := result.totalSupply;

            // Verify transfers used 33/16 ratios
            assert virtualAccounts.getBalance(caller, tokenA) == 367; // 400 - 33
            assert virtualAccounts.getBalance(caller, tokenB) == 184; // 200 - 16
            assert virtualAccounts.getBalance(systemAccount, tokenA) == 233; // 200 + 33
            assert virtualAccounts.getBalance(systemAccount, tokenB) == 116; // 100 + 16
          };
        };

        // 3. Supply decrease: 7 -> 4 supply units
        let decreaseAmount = 300;
        switch (backingImpl.processBackingDecrease(decreaseAmount, supplyUnit, totalSupply, backingTokens)) {
          case (#err(e)) { assert false };
          case (#ok(result)) {
            totalSupply := result.totalSupply;

            // Verify new backing units
            assert backingTokens[0].backingUnit == 50; // 200/4 = 50
            assert backingTokens[1].backingUnit == 25; // 100/4 = 25
          };
        };

        // 4. Redeem with new ratios (50/25)
        let redeemAmount = 100;
        let frozenTokens2 = Array.freeze(backingTokens);
        switch (backingImpl.processRedeem(caller, systemAccount, redeemAmount, supplyUnit, totalSupply, frozenTokens2)) {
          case (#err(e)) { assert false };
          case (#ok(result)) {
            totalSupply := result.totalSupply;

            // Verify transfers used 50/25 ratios
            assert virtualAccounts.getBalance(caller, tokenA) == 417; // 367 + 50
            assert virtualAccounts.getBalance(caller, tokenB) == 209; // 184 + 25
            assert virtualAccounts.getBalance(systemAccount, tokenA) == 183; // 233 - 50
            assert virtualAccounts.getBalance(systemAccount, tokenB) == 91; // 116 - 25
          };
        };
      },
    );

  },
);
