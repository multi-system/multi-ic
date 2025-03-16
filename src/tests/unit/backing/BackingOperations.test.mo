import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../../multi_backend/types/Types";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import AccountTypes "../../../multi_backend/types/AccountTypes";
import BackingStore "../../../multi_backend/backing/BackingStore";
import BackingOperations "../../../multi_backend/backing/BackingOperations";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Error "../../../multi_backend/error/Error";
import Result "mo:base/Result";
import BackingValidation "../../../multi_backend/backing/BackingValidation";
import AmountOperations "../../../multi_backend/financial/AmountOperations";

suite(
  "Backing Operations",
  func() {
    let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let tokenB : Types.Token = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let systemAccount : Types.Account = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let multiTokenLedger : Types.Token = Principal.fromText("qhbym-qaaaa-aaaaa-aaafq-cai");
    let caller : Types.Account = Principal.fromText("aaaaa-aa");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    let approveToken = func(
      store : BackingStore.BackingStore,
      caller : Types.Account,
      token : Types.Token,
    ) : Result.Result<(), Error.ApprovalError> {
      switch (BackingValidation.validateTokenApproval(token, store)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          store.addBackingToken(token);
          return #ok(());
        };
      };
    };

    let createTestEnv = func() : (BackingStore.BackingStore, BackingOperations.BackingOperations, VirtualAccounts.VirtualAccounts) {
      let state : BackingTypes.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 0;
          totalSupply = 0;
          backingPairs = [];
          multiToken = Principal.fromText("aaaaa-aa");
        };
      };

      let store = BackingStore.BackingStore(state);
      let initVAState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();
      let virtualAccounts = VirtualAccounts.VirtualAccounts(initVAState);

      let ops = BackingOperations.BackingOperations(
        store,
        virtualAccounts,
        systemAccount,
      );

      (store, ops, virtualAccounts);
    };

    let setupSystem = func(
      store : BackingStore.BackingStore,
      ops : BackingOperations.BackingOperations,
      va : VirtualAccounts.VirtualAccounts,
      initialAmountA : Nat,
      initialAmountB : Nat,
      redeemToZero : Bool,
    ) {
      let existingBalanceA = va.getBalance(caller, tokenA);
      let existingBalanceB = va.getBalance(caller, tokenB);

      if (existingBalanceA.value > 0) {
        va.burn(caller, existingBalanceA);
      };
      if (existingBalanceB.value > 0) {
        va.burn(caller, existingBalanceB);
      };

      va.mint(caller, amount(tokenA, initialAmountA));
      va.mint(caller, amount(tokenB, initialAmountB));

      assert (approveToken(store, caller, tokenA) == #ok());
      assert (approveToken(store, caller, tokenB) == #ok());

      let backingPairs = [
        {
          token = tokenA;
          backingUnit = initialAmountA / 10;
        },
        {
          token = tokenB;
          backingUnit = initialAmountB / 10;
        },
      ];

      assert (ops.processInitialize(backingPairs, 100, multiTokenLedger) == #ok());

      va.transfer({
        from = caller;
        to = systemAccount;
        amount = amount(tokenA, initialAmountA);
      });
      va.transfer({
        from = caller;
        to = systemAccount;
        amount = amount(tokenB, initialAmountB);
      });
      va.mint(caller, amount(multiTokenLedger, 1000));
      store.updateTotalSupply(amount(multiTokenLedger, 1000));

      if (redeemToZero) {
        assert (va.getBalance(caller, multiTokenLedger).value == 1000);
        assert (ops.processRedeem(caller, amount(multiTokenLedger, 1000)) == #ok());
        assert (store.getTotalSupply().value == 0);

        let remainingBalanceA = va.getBalance(caller, tokenA);
        let remainingBalanceB = va.getBalance(caller, tokenB);

        if (remainingBalanceA.value > 0) {
          va.burn(caller, remainingBalanceA);
        };
        if (remainingBalanceB.value > 0) {
          va.burn(caller, remainingBalanceB);
        };
      };
    };

    test(
      "initializes with single token successfully",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (approveToken(store, caller, tokenA) == #ok());
        va.mint(caller, amount(tokenA, 1000));

        let backingPairs = [{
          token = tokenA;
          backingUnit = 10;
        }];

        switch (ops.processInitialize(backingPairs, 100, multiTokenLedger)) {
          case (#err(e)) { assert false };
          case (#ok()) {
            assert (store.getSupplyUnit() == 100);
            assert (store.getTotalSupply().value == 0);

            va.transfer({
              from = caller;
              to = systemAccount;
              amount = amount(tokenA, 1000);
            });
            va.mint(caller, amount(multiTokenLedger, 1000));
            store.updateTotalSupply(amount(multiTokenLedger, 1000));

            assert (va.getBalance(systemAccount, tokenA).value == 1000);
            assert (va.getBalance(caller, multiTokenLedger).value == 1000);
          };
        };
      },
    );

    test(
      "prevents double initialization",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (approveToken(store, caller, tokenA) == #ok());
        va.mint(caller, amount(tokenA, 1000));

        let backingPairs = [{
          token = tokenA;
          backingUnit = 10;
        }];

        assert (ops.processInitialize(backingPairs, 100, multiTokenLedger) == #ok());

        switch (ops.processInitialize(backingPairs, 100, multiTokenLedger)) {
          case (#err(#AlreadyInitialized)) {};
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with unapproved token",
      func() {
        let (store, ops, va) = createTestEnv();
        let unauthorizedToken : Types.Token = Principal.fromText("aaaaa-aa");

        va.mint(caller, amount(unauthorizedToken, 1000));

        let backingPairs = [{
          token = unauthorizedToken;
          backingUnit = 10;
        }];

        switch (ops.processInitialize(backingPairs, 100, multiTokenLedger)) {
          case (#err(#TokenNotApproved(token))) {
            assert Principal.equal(token, unauthorizedToken);
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with zero backing unit",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (approveToken(store, caller, tokenA) == #ok());
        va.mint(caller, amount(tokenA, 500));

        let backingPairs = [{
          token = tokenA;
          backingUnit = 0;
        }];

        switch (ops.processInitialize(backingPairs, 100, multiTokenLedger)) {
          case (#err(#InvalidBackingUnit(token))) {
            assert Principal.equal(token, tokenA);
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails to initialize with zero supply unit",
      func() {
        let (store, ops, va) = createTestEnv();

        assert (approveToken(store, caller, tokenA) == #ok());
        va.mint(caller, amount(tokenA, 1000));

        let backingPairs = [{
          token = tokenA;
          backingUnit = 10;
        }];

        switch (ops.processInitialize(backingPairs, 0, multiTokenLedger)) {
          case (#err(#InvalidSupplyUnit)) {};
          case _ { assert false };
        };
      },
    );

    test(
      "handles issue with sufficient balance",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        va.mint(caller, amount(tokenA, 200));
        va.mint(caller, amount(tokenB, 100));

        switch (ops.processIssue(caller, amount(multiTokenLedger, 100))) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            assert (va.getBalance(systemAccount, tokenA).value == backingTokens[0].backingUnit);
            assert (va.getBalance(systemAccount, tokenB).value == backingTokens[1].backingUnit);
            let config = store.getConfig();
            assert (va.getBalance(caller, config.multiToken).value == 100);
          };
        };
      },
    );

    test(
      "fails issue with insufficient balance",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        let backingTokens = store.getBackingTokens();

        va.mint(caller, amount(tokenA, 50));
        va.mint(caller, amount(tokenB, 50));

        switch (ops.processIssue(caller, amount(multiTokenLedger, 100))) {
          case (#err(#InsufficientBalance({ token; required; balance }))) {
            assert Principal.equal(token, tokenA);
            assert (store.getTotalSupply().value == 0);
            assert (va.getBalance(systemAccount, tokenA).value == 0);
            assert (va.getBalance(systemAccount, tokenB).value == 0);
          };
          case _ { assert false };
        };
      },
    );

    test(
      "fails issue with unaligned supply unit",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        va.mint(caller, amount(tokenA, 200));
        va.mint(caller, amount(tokenB, 100));

        switch (ops.processIssue(caller, amount(multiTokenLedger, 150))) {
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 150;
          };
          case _ { assert false };
        };
      },
    );

    test(
      "handles complete issue/redeem cycle",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        let initialCallerA = va.getBalance(caller, tokenA);
        let initialCallerB = va.getBalance(caller, tokenB);

        va.mint(caller, amount(tokenA, 200));
        va.mint(caller, amount(tokenB, 100));
        assert (ops.processIssue(caller, amount(multiTokenLedger, 100)) == #ok());

        let issuedSystemA = va.getBalance(systemAccount, tokenA).value;
        let issuedSystemB = va.getBalance(systemAccount, tokenB).value;

        assert (ops.processRedeem(caller, amount(multiTokenLedger, 100)) == #ok());

        assert (va.getBalance(systemAccount, tokenA).value == 0);
        assert (va.getBalance(systemAccount, tokenB).value == 0);
        assert (va.getBalance(caller, tokenA).value == initialCallerA.value + 200);
        assert (va.getBalance(caller, tokenB).value == initialCallerB.value + 100);
        assert (store.getTotalSupply().value == 0);
      },
    );

    test(
      "handles complex sequence of supply changes with ratio verification",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        va.mint(caller, amount(tokenA, 400));
        va.mint(caller, amount(tokenB, 200));

        assert (ops.processIssue(caller, amount(multiTokenLedger, 200)) == #ok());

        let initialTokens = store.getBackingTokens();
        assert initialTokens[0].backingUnit == 100;
        assert initialTokens[1].backingUnit == 50;
        assert (va.getBalance(systemAccount, tokenA).value == 200);
        assert (va.getBalance(systemAccount, tokenB).value == 100);

        switch (ops.processSupplyIncrease(amount(multiTokenLedger, 400))) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            assert backingTokens[0].backingUnit == 33;
            assert backingTokens[1].backingUnit == 16;
          };
        };

        assert (ops.processIssue(caller, amount(multiTokenLedger, 100)) == #ok());

        assert va.getBalance(caller, tokenA).value == 167;
        assert va.getBalance(caller, tokenB).value == 84;
        assert va.getBalance(systemAccount, tokenA).value == 233;
        assert va.getBalance(systemAccount, tokenB).value == 116;

        switch (ops.processSupplyDecrease(amount(multiTokenLedger, 300))) {
          case (#err(e)) { assert false };
          case (#ok()) {
            let backingTokens = store.getBackingTokens();
            assert backingTokens[0].backingUnit == 58;
            assert backingTokens[1].backingUnit == 29;
          };
        };

        assert (ops.processRedeem(caller, amount(multiTokenLedger, 100)) == #ok());

        assert va.getBalance(caller, tokenA).value == 225;
        assert va.getBalance(caller, tokenB).value == 113;
        assert va.getBalance(systemAccount, tokenA).value == 175;
        assert va.getBalance(systemAccount, tokenB).value == 87;

        let finalTokens = store.getBackingTokens();
        assert (finalTokens[0].backingUnit / finalTokens[1].backingUnit == 2);
      },
    );

    test(
      "handles edge cases in supply management",
      func() {
        let (store, ops, va) = createTestEnv();
        setupSystem(store, ops, va, 1000, 500, true);

        switch (ops.processSupplyDecrease(amount(multiTokenLedger, 100))) {
          case (#err(#InvalidSupplyChange({ currentSupply; requestedChange; reason }))) {
            assert currentSupply == 0;
            assert requestedChange == 100;
            assert reason == "Cannot decrease supply by more than current supply";
          };
          case _ { assert false };
        };

        va.mint(caller, amount(tokenA, 400));
        va.mint(caller, amount(tokenB, 200));

        assert (ops.processIssue(caller, amount(multiTokenLedger, 200)) == #ok());

        let initialTokens = store.getBackingTokens();
        assert initialTokens[0].backingUnit == 100;
        assert initialTokens[1].backingUnit == 50;

        switch (ops.processSupplyDecrease(amount(multiTokenLedger, 150))) {
          case (#err(#InvalidAmount({ reason; amount }))) {
            assert reason == "Amount must be divisible by supply unit";
            assert amount == 150;
          };
          case _ { assert false };
        };

        assert (ops.processSupplyIncrease(amount(multiTokenLedger, 1000)) == #ok());
        let afterIncreaseTokens = store.getBackingTokens();
        assert afterIncreaseTokens[0].backingUnit == 16;
        assert afterIncreaseTokens[1].backingUnit == 8;

        assert (afterIncreaseTokens[0].backingUnit / afterIncreaseTokens[1].backingUnit == 2);

        assert (va.getBalance(systemAccount, tokenA).value == 200);
        assert (va.getBalance(systemAccount, tokenB).value == 100);
      },
    );
  },
);
