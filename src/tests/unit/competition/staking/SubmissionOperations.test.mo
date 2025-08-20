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
import StakeCalculator "../../../../multi_backend/competition/staking/StakeCalculator";
import StakingManager "../../../../multi_backend/competition/staking/StakingManager";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Submission Operations",
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

    test(
      "creates a valid submission with correct properties",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        switch (result) {
          case (#err(error)) {
            Debug.print("Unexpected error: " # debug_show (error));
            assert (false);
          };
          case (#ok(output)) {
            // Verify submission properties
            assert (output.submissionId == 0);

            // Get the submission from the store
            let submissions = competitionEntry.getAllSubmissions();
            assert (submissions.size() == 1);

            let submission = submissions[0];
            assert (Principal.equal(submission.participant, user));
            assert (Principal.equal(submission.token, testToken));
            assert (submission.proposedQuantity.value == output.tokenQuantity.value);
            assert (submission.status == #Staked);
            assert (submission.rejectionReason == null);
            assert (submission.adjustedQuantity == null);
            assert (submission.soldQuantity == null);
            assert (submission.executionPrice == null);
            assert (submission.positionId == null);

            // Verify stakes in the flexible array format
            assert (submission.stakes.size() == 2);
            let (govToken, govStakeAmount) = submission.stakes[0];
            let (multiToken, multiStakeAmount) = submission.stakes[1];
            assert (govStakeAmount.value == 1000);
            assert (multiStakeAmount.value == 200); // Calculated from rates
          };
        };
      },
    );

    test(
      "processes valid submission correctly",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        switch (result) {
          case (#err(_)) {
            assert (false);
          };
          case (#ok(output)) {
            // Verify the submission was processed correctly
            let allSubmissions = competitionEntry.getAllSubmissions();
            assert (allSubmissions.size() == 1);
            assert (allSubmissions[0].id == output.submissionId);
            assert (allSubmissions[0].status == #Staked);

            // Verify that token balances were updated
            let stakeAccounts = stakeVault.getStakeAccounts();
            assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getGovToken()).value == 1000);
            assert (stakeAccounts.getBalance(user, CompetitionTestUtils.getMultiToken()).value == 200);
            assert (stakeAccounts.getBalance(user, testToken).value == output.tokenQuantity.value);

            // Verify total stakes were updated in the store
            let totalStakes = competitionEntry.getStakeVault().getAllTotalStakes();
            assert (totalStakes.size() == 2);
          };
        };
      },
    );

    test(
      "competition must be active for processing submissions",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        // Set competition inactive
        competitionEntry.updateStatus(#PreAnnouncement);

        // Verify the competition is inactive
        assert (competitionEntry.getStatus() != #AcceptingStakes);

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Should return an InvalidPhase error
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (_) {
            assert (false); // Wrong result
          };
        };
      },
    );

    test(
      "rejects submission with insufficient balance",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1_000_000; // More than user has
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = stakingManager.acceptStakeRequest(
          govStake,
          user,
          testToken,
        );

        // Verify we get the right error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InsufficientStake({ token; required; available }))) {
            // With 1M gov stake at 5% rate and 1% multi rate:
            // multiStake = 1M * (1%/5%) = 200,000
            // tokenQuantity = 200,000 / (1% * 1.0) = 20,000,000
            // User has only 10,000,000 of testToken1, so this fails first
            assert (Principal.equal(token, testToken));
            assert (required == 20_000_000);
            assert (available == 10_000_000);
          };
          case (#err(_)) {
            assert (false); // Should not get other errors
          };
        };
      },
    );

    test(
      "correctly adjusts quantities when rates increase",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Process initial stake request
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
            let originalQuantity = output.tokenQuantity.value;

            // Use higher rates for adjustment
            let updatedRates : [(Types.Token, Types.Ratio)] = [
              (CompetitionTestUtils.getGovToken(), { value = CompetitionTestUtils.getTEN_PERCENT() }), // Double
              (CompetitionTestUtils.getMultiToken(), { value = CompetitionTestUtils.getTWO_PERCENT() }), // Double
            ];

            // Finalize the submission with new rates
            let finalizeResult = stakingManager.finalizeSubmission(
              submissionId,
              updatedRates,
            );

            switch (finalizeResult) {
              case (#err(error)) {
                Debug.print("Finalization failed: " # debug_show (error));
                assert (false);
              };
              case (#ok(adjustedSubmission)) {
                assert (adjustedSubmission.status == #Finalized);

                let adjustedQuantity = switch (adjustedSubmission.adjustedQuantity) {
                  case (null) { assert (false); 0 };
                  case (?adjusted) { adjusted.value };
                };

                // When rates double, quantity should approximately halve
                assert (adjustedQuantity < originalQuantity);

                // Verify excess tokens were returned to user
                let userBalance = stakeVault.getUserAccounts().getBalance(user, testToken);
                assert (userBalance.value > 0);
              };
            };
          };
        };
      },
    );

    test(
      "handles equal rates correctly",
      func() {
        let (competitionEntry, stakingManager, user) = setupTest();
        let stakeVault = competitionEntry.getStakeVault();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Process initial stake request
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
            let originalQuantity = output.tokenQuantity.value;

            // Use the same rates for finalization
            let sameRates : [(Types.Token, Types.Ratio)] = [
              (CompetitionTestUtils.getGovToken(), { value = CompetitionTestUtils.getFIVE_PERCENT() }),
              (CompetitionTestUtils.getMultiToken(), { value = CompetitionTestUtils.getONE_PERCENT() }),
            ];

            // Finalize the submission with same rates
            let finalizeResult = stakingManager.finalizeSubmission(
              submissionId,
              sameRates,
            );

            switch (finalizeResult) {
              case (#err(error)) {
                Debug.print("Finalization failed: " # debug_show (error));
                assert (false);
              };
              case (#ok(adjustedSubmission)) {
                assert (adjustedSubmission.status == #Finalized);

                let adjustedQuantity = switch (adjustedSubmission.adjustedQuantity) {
                  case (null) { assert (false); 0 };
                  case (?adjusted) { adjusted.value };
                };

                // With equal rates, adjusted quantity equals original quantity
                assert (adjustedQuantity == originalQuantity);
              };
            };
          };
        };
      },
    );
  },
);
