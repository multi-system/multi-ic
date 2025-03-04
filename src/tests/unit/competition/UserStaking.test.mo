import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import UserStaking "../../../multi_backend/competition/UserStaking";
import AmountOperations "../../../multi_backend/financial/AmountOperations";
import StakeSubmissionTypes "../../../multi_backend/competition/StakeSubmissionTypes";
import AccountTypes "../../../multi_backend/types/AccountTypes";

suite(
  "User Staking",
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

    // Helper to setup fresh accounts and staking for each test
    let setupTest = func() : (VirtualAccounts.VirtualAccounts, UserStaking.UserStaking) {
      let initVAState = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
      let userAccounts = VirtualAccounts.VirtualAccounts(initVAState);

      // Initialize user accounts with balances
      userAccounts.mint(user1, amount(govToken, 1000));
      userAccounts.mint(user1, amount(multiToken, 2000));
      userAccounts.mint(user1, amount(proposedToken, 3000));

      userAccounts.mint(user2, amount(govToken, 500));
      userAccounts.mint(user2, amount(multiToken, 700));
      userAccounts.mint(user2, amount(proposedToken, 900));

      let staking = UserStaking.UserStaking(
        userAccounts,
        multiToken,
        govToken,
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
      "recordSubmission stakes governance tokens, multi tokens, and proposed quantity",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Initial balances
        assert (userAccounts.getBalance(user1, govToken).value == 1000);
        assert (userAccounts.getBalance(user1, multiToken).value == 2000);
        assert (userAccounts.getBalance(user1, proposedToken).value == 3000);

        // Record submission
        let result = staking.recordSubmission(
          user1,
          amount(proposedToken, 1000),
          amount(govToken, 200),
          amount(multiToken, 300),
        );

        // Submission should succeed
        switch (result) {
          case (#ok(submissionId)) {
            assert (submissionId == 0);
          };
          case (#err(_)) {
            assert (false); // Should not error
          };
        };

        // Check balances after submission
        assert (userAccounts.getBalance(user1, govToken).value == 800);
        assert (userAccounts.getBalance(user1, multiToken).value == 1700);
        assert (userAccounts.getBalance(user1, proposedToken).value == 2000);

        assert (stakeAccounts.getBalance(user1, govToken).value == 200);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 300);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 1000);
      },
    );

    test(
      "recordSubmission fails with insufficient governance token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Try to stake more governance tokens than available
        let result = staking.recordSubmission(
          user1,
          amount(proposedToken, 100),
          amount(govToken, 2000), // User only has 1000
          amount(multiToken, 100),
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
      "recordSubmission fails with insufficient multi token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Try to stake more multi tokens than available
        let result = staking.recordSubmission(
          user1,
          amount(proposedToken, 100),
          amount(govToken, 100),
          amount(multiToken, 3000) // User only has 2000
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
      "recordSubmission fails with insufficient proposed token balance",
      func() {
        let (userAccounts, staking) = setupTest();
        let stakeAccounts = staking.getStakeAccounts();

        // Try to stake more proposed tokens than available
        let result = staking.recordSubmission(
          user1,
          amount(proposedToken, 4000), // User only has 3000
          amount(govToken, 100),
          amount(multiToken, 100),
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
      "getSubmission returns null for non-existent submission ID",
      func() {
        let (_, staking) = setupTest();

        let submission = staking.getSubmission(100);
        assert (submission == null);
      },
    );

    test(
      "getSubmission returns correct submission",
      func() {
        let (_, staking) = setupTest();

        // Record a submission
        let govStakeAmount = amount(govToken, 200);
        let multiStakeAmount = amount(multiToken, 300);
        let proposedAmount = amount(proposedToken, 1000);

        let result = staking.recordSubmission(
          user1,
          proposedAmount,
          govStakeAmount,
          multiStakeAmount,
        );

        // Get submission ID
        var submissionId : StakeSubmissionTypes.SubmissionId = 0;
        switch (result) {
          case (#ok(id)) { submissionId := id };
          case (#err(_)) { assert (false) };
        };

        // Get submission and verify details
        let submissionOpt = staking.getSubmission(submissionId);
        switch (submissionOpt) {
          case (null) {
            assert (false); // Should exist
          };
          case (?submission) {
            assert (submission.id == submissionId);
            assert (Principal.equal(submission.participant, user1));
            assert (AmountOperations.equal(submission.proposedQuantity, proposedAmount));
            assert (AmountOperations.equal(submission.govStake, govStakeAmount));
            assert (AmountOperations.equal(submission.multiStake, multiStakeAmount));
            assert (submission.finalQuantity == null);
          };
        };
      },
    );

    test(
      "getAllSubmissions returns all recorded submissions",
      func() {
        let (_, staking) = setupTest();

        // Initial submissions array should be empty
        assert (staking.getAllSubmissions().size() == 0);

        // Record submissions for user1 and user2
        let _ = staking.recordSubmission(
          user1,
          amount(proposedToken, 1000),
          amount(govToken, 200),
          amount(multiToken, 300),
        );

        let _ = staking.recordSubmission(
          user2,
          amount(proposedToken, 500),
          amount(govToken, 100),
          amount(multiToken, 200),
        );

        // Check submissions
        let submissions = staking.getAllSubmissions();
        assert (submissions.size() == 2);

        // Check first submission
        assert (submissions[0].id == 0);
        assert (Principal.equal(submissions[0].participant, user1));

        // Check second submission
        assert (submissions[1].id == 1);
        assert (Principal.equal(submissions[1].participant, user2));
      },
    );

    test(
      "getTotalGovernanceStake returns sum of all governance stakes",
      func() {
        let (_, staking) = setupTest();

        // Initially zero
        assert (staking.getTotalGovernanceStake() == 0);

        // Record submissions for user1 and user2
        let _ = staking.recordSubmission(
          user1,
          amount(proposedToken, 1000),
          amount(govToken, 200),
          amount(multiToken, 300),
        );

        let _ = staking.recordSubmission(
          user2,
          amount(proposedToken, 500),
          amount(govToken, 100),
          amount(multiToken, 200),
        );

        // Check total governance stake: 200 + 100 = 300
        assert (staking.getTotalGovernanceStake() == 300);
      },
    );

    test(
      "getTotalMultiStake returns sum of all multi stakes",
      func() {
        let (_, staking) = setupTest();

        // Initially zero
        assert (staking.getTotalMultiStake() == 0);

        // Record submissions for user1 and user2
        let _ = staking.recordSubmission(
          user1,
          amount(proposedToken, 1000),
          amount(govToken, 200),
          amount(multiToken, 300),
        );

        let _ = staking.recordSubmission(
          user2,
          amount(proposedToken, 500),
          amount(govToken, 100),
          amount(multiToken, 200),
        );

        // Check total multi stake: 300 + 200 = 500
        assert (staking.getTotalMultiStake() == 500);
      },
    );

    test(
      "getStakeAccounts returns the stake accounts",
      func() {
        let (_, staking) = setupTest();

        // Get stake accounts
        let stakeAccounts = staking.getStakeAccounts();

        // Verify it's a usable VirtualAccounts instance
        assert (stakeAccounts.getBalance(user1, govToken).value == 0);

        // Record a submission
        let _ = staking.recordSubmission(
          user1,
          amount(proposedToken, 1000),
          amount(govToken, 200),
          amount(multiToken, 300),
        );

        // Check balances in the returned stake accounts
        assert (stakeAccounts.getBalance(user1, govToken).value == 200);
        assert (stakeAccounts.getBalance(user1, multiToken).value == 300);
        assert (stakeAccounts.getBalance(user1, proposedToken).value == 1000);
      },
    );
  },
);
