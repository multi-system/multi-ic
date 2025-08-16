import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import AmountOperations "../../../../multi_backend/financial/AmountOperations";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import AccountTypes "../../../../multi_backend/types/AccountTypes";
import StakeTokenTypes "../../../../multi_backend/types/StakeTokenTypes";

suite(
  "Stake Vault",
  func() {
    // Setup test tokens
    let govToken : Types.Token = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let multiToken : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let proposedToken : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    // Setup test user accounts
    let user1 : Types.Account = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let user2 : Types.Account = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");

    // Helper to create amount objects
    let amount = func(token : Types.Token, value : Nat) : Types.Amount {
      { token; value };
    };

    // Create stake token configurations
    let createStakeTokenConfigs = func() : [StakeTokenTypes.StakeTokenConfig] {
      [
        {
          token = govToken;
          baseRate = { value = 50_000_000 }; // 5%
          systemMultiplier = { value = 200_000_000 }; // 20%
        },
        {
          token = multiToken;
          baseRate = { value = 10_000_000 }; // 1%
          systemMultiplier = { value = 500_000_000 }; // 50%
        },
      ];
    };

    // Helper to setup fresh accounts and staking for each test
    let setupTest = func() : (VirtualAccounts.VirtualAccounts, StakeVault.StakeVault) {
      let initVAState = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
      let userAccounts = VirtualAccounts.VirtualAccounts(initVAState);

      // Initialize user accounts with balances
      userAccounts.mint(user1, amount(govToken, 1000));
      userAccounts.mint(user1, amount(multiToken, 2000));
      userAccounts.mint(user1, amount(proposedToken, 3000));

      userAccounts.mint(user2, amount(govToken, 500));
      userAccounts.mint(user2, amount(multiToken, 700));
      userAccounts.mint(user2, amount(proposedToken, 900));

      // Create empty stake accounts map for the stake vault
      let initStakeState = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();

      let staking = StakeVault.StakeVault(
        userAccounts,
        createStakeTokenConfigs(),
        initStakeState,
      );

      (userAccounts, staking);
    };

    test(
      "stake transfers tokens from user account to stake account",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Initial balances
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (stakeAccounts.getBalance(user1, govToken).value == 0);

        // Perform stake
        staking.stake(user1, amount(govToken, 500));

        // Check balances after stake
        assert (userAccounts.getBalance(user1, govToken).value == 500);
        assert (stakeAccounts.getBalance(user1, govToken).value == 500);
      },
    );

    test(
      "executeStakeTransfers transfers tokens from user account to stake account",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Initial balances
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (userAccounts.getBalance(user1, multiToken).value == 2000);
        assert (userAccounts.getBalance(user1, proposedToken).value == 3000);

        // Create stakes array
        let stakes : [(Types.Token, Types.Amount)] = [
          (govToken, amount(govToken, 200)),
          (multiToken, amount(multiToken, 300)),
        ];

        // Perform executeStakeTransfers
        let result = staking.executeStakeTransfers(
          user1,
          amount(proposedToken, 1000),
          stakes,
        );

        // Staking should succeed
        switch (result) {
          case (#ok(_)) {
            // Expected success case
          };
          case (#err(_)) {
            assert (false); // Should not error
          };
        };

        // Check balances after staking
        assert (userAccounts.getBalance(user1, govToken).value == 800);
        assert (userAccounts.getBalance(user1, multiToken).value == 1700);
        assert (userAccounts.getBalance(user1, proposedToken).value == 2000);

        assert (stakeAccounts.getBalance(user1, govToken).value == 200);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 300);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 1000);
      },
    );

    test(
      "executeStakeTransfers fails with insufficient governance token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Create stakes array with excessive governance tokens
        let stakes : [(Types.Token, Types.Amount)] = [
          (govToken, amount(govToken, 2000)), // User only has 1000
          (multiToken, amount(multiToken, 100)),
        ];

        // Try to stake more governance tokens than available
        let result = staking.executeStakeTransfers(
          user1,
          amount(proposedToken, 100),
          stakes,
        );

        // Submission should fail
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should error
          };
          case (#err(error)) {
            switch (error) {
              case (#InsufficientStake(details)) {
                assert (Principal.equal(details.token, govToken));
                assert (details.required == 2000);
                assert (details.available == 1000);
              };
              case (_) {
                assert (false); // Wrong error type
              };
            };
          };
        };

        // Balances should remain unchanged
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (userAccounts.getBalance(user1, multiToken).value == 2000);
        assert (userAccounts.getBalance(user1, proposedToken).value == 3000);

        assert (stakeAccounts.getBalance(user1, govToken).value == 0);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 0);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 0);
      },
    );

    test(
      "executeStakeTransfers fails with insufficient multi token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Create stakes array with excessive multi tokens
        let stakes : [(Types.Token, Types.Amount)] = [
          (govToken, amount(govToken, 100)),
          (multiToken, amount(multiToken, 3000)), // User only has 2000
        ];

        // Try to stake more multi tokens than available
        let result = staking.executeStakeTransfers(
          user1,
          amount(proposedToken, 100),
          stakes,
        );

        // Submission should fail
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should error
          };
          case (#err(error)) {
            switch (error) {
              case (#InsufficientStake(details)) {
                assert (Principal.equal(details.token, multiToken));
                assert (details.required == 3000);
                assert (details.available == 2000);
              };
              case (_) {
                assert (false); // Wrong error type
              };
            };
          };
        };

        // Balances should remain unchanged
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (userAccounts.getBalance(user1, multiToken).value == 2000);
        assert (userAccounts.getBalance(user1, proposedToken).value == 3000);

        assert (stakeAccounts.getBalance(user1, govToken).value == 0);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 0);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 0);
      },
    );

    test(
      "executeStakeTransfers fails with insufficient proposed token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Create stakes array
        let stakes : [(Types.Token, Types.Amount)] = [
          (govToken, amount(govToken, 100)),
          (multiToken, amount(multiToken, 100)),
        ];

        // Try to stake more proposed tokens than available
        let result = staking.executeStakeTransfers(
          user1,
          amount(proposedToken, 4000), // User only has 3000
          stakes,
        );

        // Submission should fail
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should error
          };
          case (#err(error)) {
            switch (error) {
              case (#InsufficientStake(details)) {
                assert (Principal.equal(details.token, proposedToken));
                assert (details.required == 4000);
                assert (details.available == 3000);
              };
              case (_) {
                assert (false); // Wrong error type
              };
            };
          };
        };

        // Balances should remain unchanged
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (userAccounts.getBalance(user1, multiToken).value == 2000);
        assert (userAccounts.getBalance(user1, proposedToken).value == 3000);

        assert (stakeAccounts.getBalance(user1, govToken).value == 0);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 0);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 0);
      },
    );

    test(
      "returnExcessTokens transfers tokens back to user account",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // First stake some tokens
        staking.stake(user1, amount(proposedToken, 1000));

        // Initial balances after staking
        assert (userAccounts.getBalance(user1, proposedToken).value == 2000);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 1000);

        // Return some excess tokens
        staking.returnExcessTokens(user1, amount(proposedToken, 300));

        // Check balances after returning
        assert (userAccounts.getBalance(user1, proposedToken).value == 2300);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 700);
      },
    );

    test(
      "getTotalStakeForToken returns sum of all stakes for specific token",
      func() {
        let (userAccounts, staking) = setupTest();

        // Initially zero
        assert (staking.getTotalStakeForToken(govToken) == 0);

        // Stake for user1 and user2
        staking.stake(user1, amount(govToken, 200));
        staking.stake(user2, amount(govToken, 100));

        // Check total governance stake: 200 + 100 = 300
        assert (staking.getTotalStakeForToken(govToken) == 300);
      },
    );

    test(
      "getAllTotalStakes returns sum of all configured stake tokens",
      func() {
        let (userAccounts, staking) = setupTest();

        // Initially all zero
        let initialStakes = staking.getAllTotalStakes();
        assert (initialStakes.size() == 2); // Two configured stake tokens
        for ((token, total) in initialStakes.vals()) {
          assert (total == 0);
        };

        // Stake for user1 and user2
        staking.stake(user1, amount(govToken, 200));
        staking.stake(user1, amount(multiToken, 300));
        staking.stake(user2, amount(govToken, 100));
        staking.stake(user2, amount(multiToken, 200));

        // Check total stakes
        let totalStakes = staking.getAllTotalStakes();
        assert (totalStakes.size() == 2);

        // Find and verify each token's total
        for ((token, total) in totalStakes.vals()) {
          if (Principal.equal(token, govToken)) {
            assert (total == 300); // 200 + 100
          } else if (Principal.equal(token, multiToken)) {
            assert (total == 500); // 300 + 200
          } else {
            assert (false); // Unexpected token
          };
        };
      },
    );

    test(
      "getStakeAccounts returns the stake accounts",
      func() {
        let (userAccounts, staking) = setupTest();

        // Get stake accounts
        let stakeAccounts = staking.getStakeAccounts();

        // Verify it's a usable VirtualAccounts instance
        assert (stakeAccounts.getBalance(user1, govToken).value == 0);

        // Stake some tokens
        staking.stake(user1, amount(govToken, 200));
        staking.stake(user1, amount(multiToken, 300));
        staking.stake(user1, amount(proposedToken, 1000));

        // Check balances in the returned stake accounts
        assert (stakeAccounts.getBalance(user1, govToken).value == 200);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 300);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 1000);
      },
    );

    test(
      "getStakeAccountsMap returns map that can be used to persist state",
      func() {
        let (userAccounts, staking) = setupTest();

        // Stake some tokens
        staking.stake(user1, amount(govToken, 200));
        staking.stake(user1, amount(multiToken, 300));

        // Get the stake accounts map
        let stakeAccountsMap = staking.getStakeAccountsMap();

        // Create a new stake vault with the saved map
        let newStaking = StakeVault.StakeVault(
          userAccounts,
          createStakeTokenConfigs(),
          stakeAccountsMap,
        );

        // Verify the new vault has the same balances
        let newStakeAccounts = newStaking.getStakeAccounts();
        assert (newStakeAccounts.getBalance(user1, govToken).value == 200);
        assert (newStakeAccounts.getBalance(user1, multiToken).value == 300);
      },
    );
  },
);
