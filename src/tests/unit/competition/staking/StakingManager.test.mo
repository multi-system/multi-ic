import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import StakingManager "../../../../multi_backend/competition/staking/StakingManager";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Staking Manager",
  func() {
    // Setup test environment for each test
    let setupTest = func() : (
      CompetitionEntryStore.CompetitionEntryStore,
      StakingManager.StakingManager,
      Types.Account,
    ) {
      let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
      let testUser = CompetitionTestUtils.getUserPrincipal();

      let getCirculatingSupply = CompetitionTestUtils.createCirculatingSupplyFunction(1_000_000);
      let getBackingTokens = CompetitionTestUtils.getBackingTokensFunction();

      let stakingManager = StakingManager.StakingManager(
        competitionEntry,
        getCirculatingSupply,
        getBackingTokens,
      );

      competitionEntry.updateStatus(#AcceptingStakes);

      (competitionEntry, stakingManager, testUser);
    };

    // Test direct stake processing
    test(
      "acceptStakeRequest - processes stake request successfully",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        // Create test input
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Call the function under test
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Verify the result
        switch (result) {
          case (#err(error)) {
            Debug.print("Unexpected error: " # debug_show (error));
            assert (false); // Should not fail
          };
          case (#ok(output)) {
            // Check submission ID was assigned
            assert (output.submissionId == 0); // First submission should have ID 0

            // Check token quantity calculation
            // For 5% gov rate and 1% multi rate with 1.0 price:
            // govStake = 1000
            // multiStake = 1000 * (1%/5%) = 200
            // tokenQuantity = 200 / (1% * 1.0) = 20,000
            assert (output.tokenQuantity.value == 20_000);

            // Check stake vault has received the tokens
            let stakeAccounts = stakeVault.getStakeAccounts();
            assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getGovToken()).value == 1000);
            assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getMultiToken()).value == 200);
            assert (stakeAccounts.getBalance(user, testToken).value == 20_000);

            // Check submission was added to store with correct status
            let submissions = competitionEntry.getAllSubmissions();
            assert (submissions.size() == 1);
            assert (submissions[0].status == #Staked);
          };
        };
      },
    );

    // Test multiple stake processing
    test(
      "acceptStakeRequest - processes multiple stake requests",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        // Process two submissions
        let govStake1 : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken1 = CompetitionTestUtils.getTestToken1();

        let govStake2 : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 2000;
        };
        let testToken2 = CompetitionTestUtils.getTestToken2();

        // Process both submissions immediately
        ignore stakingManager.acceptStakeRequest(govStake1, user, testToken1);
        ignore stakingManager.acceptStakeRequest(govStake2, user, testToken2);

        // Check submissions were processed
        let submissions = competitionEntry.getAllSubmissions();
        assert (submissions.size() == 2);

        // All submissions should be Staked
        for (submission in submissions.vals()) {
          assert (submission.status == #Staked);
        };

        // Check stake vault has received all the tokens
        let stakeAccounts = stakeVault.getStakeAccounts();
        assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getGovToken()).value == 3000); // 1000 + 2000

        // Multi stake for 1000 gov stake = 200, for 2000 gov stake = 400
        assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getMultiToken()).value == 600); // 200 + 400

        // Token quantities - token2 has double the price, so quantity matches token1 despite double stake
        assert (stakeAccounts.getBalance(user, testToken1).value == 20_000);
        assert (stakeAccounts.getBalance(user, testToken2).value == 20_000);
      },
    );

    // Test error handling
    test(
      "acceptStakeRequest - returns error when competition inactive",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        // Set competition inactive
        competitionEntry.updateStatus(#PreAnnouncement);

        // Create test input
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Try to process a stake request
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Verify the error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "acceptStakeRequest - returns error for invalid token",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        // Create test input with invalid gov token
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getTestToken1(); // Not the gov token
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Try to process a stake request
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Verify the error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InvalidSubmission(_))) {
            // Expected error for wrong token type
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "acceptStakeRequest - returns error for unapproved token",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        // Create test input with valid gov stake but unapproved target token
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let unapprovedToken = Principal.fromText("aaaaa-aa"); // Not in approved list

        // Try to process a stake request
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          unapprovedToken,
        );

        // Verify the error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#TokenNotApproved(token))) {
            assert (Principal.equal(token, unapprovedToken));
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "acceptStakeRequest - returns error for insufficient balance",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        // Create test input with stake larger than user balance
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1_000_000; // User only has 100,000 in test setup
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Try to process a stake request
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Verify the error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InsufficientStake({ token; required; available }))) {
            assert (Principal.equal(token, CompetitionTestUtils.getGovToken()));
            assert (required == 1_000_000);
            assert (available == 100_000); // From test setup
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "finalization process works correctly",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        // Create and process a submission
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Process the stake request
        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        switch (result) {
          case (#err(error)) {
            Debug.print("Setup failed: " # debug_show (error));
            assert (false);
          };
          case (#ok(output)) {
            let submissionId = output.submissionId;

            // Now finalize the submission with doubled rates
            let updatedGovRate = {
              value = CompetitionTestUtils.getTEN_PERCENT();
            }; // 10% (double initial 5%)
            let updatedMultiRate = {
              value = CompetitionTestUtils.getTWO_PERCENT();
            }; // 2% (double initial 1%)

            let finalizeResult = stakingManager.finalizeSubmission(
              submissionId,
              updatedGovRate,
              updatedMultiRate,
            );

            switch (finalizeResult) {
              case (#err(error)) {
                Debug.print("Finalization failed: " # debug_show (error));
                assert (false);
              };
              case (#ok(finalizedSubmission)) {
                // Verify the submission was properly finalized
                assert (finalizedSubmission.status == #Finalized);

                // Adjusted quantity should be about half the original (since rates doubled)
                let adjustedQuantity = switch (finalizedSubmission.adjustedQuantity) {
                  case (null) { assert (false); 0 };
                  case (?adjusted) { adjusted.value };
                };

                // Original quantity should be around 20,000, adjusted should be around 10,000
                assert (adjustedQuantity < finalizedSubmission.proposedQuantity.value);

                // Check that excess tokens were returned to user
                let userBalance = stakeVault.getUserAccounts().getBalance(user, testToken);
                assert (userBalance.value > 0);
              };
            };
          };
        };
      },
    );
  },
);
