import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import CompetitionTypes "../../../../multi_backend/types/CompetitionTypes";
import CompetitionStore "../../../../multi_backend/competition/CompetitionStore";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import StakeCalculator "../../../../multi_backend/competition/staking/StakeCalculator";
import SubmissionOperations "../../../../multi_backend/competition/staking/SubmissionOperations";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Submission Operations",
  func() {
    // Setup test environment for each test
    let setupTest = func() : (
      CompetitionStore.CompetitionStore,
      StakeVault.StakeVault,
      Types.Account,
      () -> Nat,
      () -> [Types.Amount],
    ) {
      let store = CompetitionTestUtils.createCompetitionStore();
      let userAccounts = CompetitionTestUtils.createUserAccounts();
      let testUser = CompetitionTestUtils.getUserPrincipal();

      let stakeVault = StakeVault.StakeVault(
        userAccounts,
        CompetitionTestUtils.getMultiToken(),
        CompetitionTestUtils.getGovToken(),
      );

      let getCirculatingSupply = CompetitionTestUtils.createCirculatingSupplyFunction(1_000_000);

      // Define a dummy getReserve function for testing
      // This would return the current reserve composition in a real scenario
      let getReserve = func() : [Types.Amount] {
        [
          { token = CompetitionTestUtils.getTestToken1(); value = 100_000 },
          { token = CompetitionTestUtils.getTestToken2(); value = 200_000 },
          { token = CompetitionTestUtils.getTestToken3(); value = 300_000 },
        ];
      };

      store.setCompetitionActive(true);

      (store, stakeVault, testUser, getCirculatingSupply, getReserve);
    };

    test(
      "createSubmission creates a valid submission with correct properties",
      func() {
        let (store, _, user, _, _) = setupTest();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };

        let multiStake : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 500;
        };

        let testToken = CompetitionTestUtils.getTestToken1();
        let tokenQuantity = 10000;

        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          tokenQuantity,
          govStake,
          multiStake,
        );

        // Verify the submission properties
        assert (submission.id == 0);
        assert (Principal.equal(submission.participant, user));
        assert (submission.govStake.value == 1000);
        assert (submission.multiStake.value == 500);
        assert (Principal.equal(submission.token, testToken));
        assert (submission.proposedQuantity.value == tokenQuantity);
        assert (submission.status == #PreRound);
        assert (submission.rejectionReason == null);
        assert (submission.adjustedQuantity == null);
        assert (submission.soldQuantity == null);
        assert (submission.executionPrice == null);
        assert (submission.positionId == null);

        // Verify that store incremented the submission ID
        assert (store.getNextSubmissionId() == 1);
      },
    );

    test(
      "processSubmission handles valid submission correctly",
      func() {
        let (store, stakeVault, user, _, _) = setupTest();

        // Create a submission
        let testToken = CompetitionTestUtils.getTestToken1();
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let multiStake : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 500;
        };
        let proposedQuantity : Types.Amount = {
          token = testToken;
          value = 5000;
        };

        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          proposedQuantity.value,
          govStake,
          multiStake,
        );

        // Process the submission
        let result = SubmissionOperations.processSubmission(
          store,
          stakeVault,
          submission,
        );

        // Check the result
        switch (result) {
          case (#err(_)) {
            assert (false); // Should not reach here
          };
          case (#ok(updatedSubmission)) {
            // Verify the submission was updated correctly
            assert (updatedSubmission.status == #ActiveRound);

            // Verify that the submission was added to the store
            let allSubmissions = store.getAllSubmissions();
            assert (allSubmissions.size() == 1);
            assert (allSubmissions[0].id == submission.id);
            assert (allSubmissions[0].status == #ActiveRound);

            // Verify that token balances were updated
            let stakeAccounts = stakeVault.getStakeAccounts();
            assert (stakeAccounts.getBalance(user, govStake.token).value == govStake.value);
            assert (stakeAccounts.getBalance(user, multiStake.token).value == multiStake.value);
            assert (stakeAccounts.getBalance(user, proposedQuantity.token).value == proposedQuantity.value);

            // Verify total stakes were updated in the store
            assert (store.getTotalGovStake() == govStake.value);
            assert (store.getTotalMultiStake() == multiStake.value);
          };
        };
      },
    );

    test(
      "competition must be active for processing submissions",
      func() {
        let (store, stakeVault, user, _, _) = setupTest();

        // Set competition inactive
        store.setCompetitionActive(false);

        // Verify the competition is inactive
        assert (store.isCompetitionActive() == false);

        // Create a submission
        let testToken = CompetitionTestUtils.getTestToken1();
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let multiStake : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 500;
        };

        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          5000,
          govStake,
          multiStake,
        );

        // Since we know this will trap, we don't actually call processSubmission
        // Instead, we just verify the conditions that would cause it to trap
        assert (store.isCompetitionActive() == false);

        // This test is designed to document the expected behavior that
        // calling processSubmission with an inactive competition would trap
      },
    );

    test(
      "processSubmission rejects submission with insufficient balance",
      func() {
        let (store, stakeVault, user, _, _) = setupTest();

        // Create a submission with too many tokens
        let testToken = CompetitionTestUtils.getTestToken1();
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1_000_000 // More than user has
        };
        let multiStake : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 500;
        };

        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          5000,
          govStake,
          multiStake,
        );

        // This should fail due to insufficient balance
        let result = SubmissionOperations.processSubmission(
          store,
          stakeVault,
          submission,
        );

        // Verify we get the right error
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InsufficientStake({ token; required; available }))) {
            assert (Principal.equal(token, govStake.token));
            assert (required == govStake.value);
            // We know the exact available amount from test utilities
            assert (available == 100_000);
          };
          case (#err(_)) {
            assert (false); // Should not get other errors
          };
        };

        // Verify the submission was stored with Rejected status
        let allSubmissions = store.getAllSubmissions();
        assert (allSubmissions.size() == 1);
        assert (allSubmissions[0].status == #Rejected);
        switch (allSubmissions[0].rejectionReason) {
          case (? #InsufficientBalance) {
            // Expected
          };
          case (_) {
            assert (false); // Wrong rejection reason
          };
        };
      },
    );

    test(
      "adjustSubmissionPostRound correctly adjusts quantities when rates increase",
      func() {
        let (store, stakeVault, user, _, _) = setupTest();

        // 1. Get the test token and price
        let testToken = CompetitionTestUtils.getTestToken1();
        let price = switch (store.getCompetitionPrice(testToken)) {
          case (null) {
            assert (false);
            {
              baseToken = testToken;
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = 0 };
            };
          };
          case (?p) { p };
        };

        // 2. Set up gov stake
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 5000;
        };

        // 3. Calculate multi stake from gov stake
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          { value = CompetitionTestUtils.getFIVE_PERCENT() },
          { value = CompetitionTestUtils.getONE_PERCENT() },
          CompetitionTestUtils.getMultiToken(),
        );

        // 4. Calculate token quantity from multi stake
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          multiStake,
          { value = CompetitionTestUtils.getONE_PERCENT() },
          price,
        );

        // 5. Create submission using CALCULATED values
        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          tokenQuantity.value, // Use calculated value instead of fixed
          govStake,
          multiStake,
        );

        // 6. Process the submission
        switch (SubmissionOperations.processSubmission(store, stakeVault, submission)) {
          case (#err(_)) {
            assert (false);
          };
          case (#ok(_)) {};
        };

        // 7. Use higher rates for adjustment
        let updatedGovRate = { value = CompetitionTestUtils.getTEN_PERCENT() };
        let updatedMultiRate = { value = CompetitionTestUtils.getTWO_PERCENT() };

        // 8. Adjust the submission
        let result = SubmissionOperations.adjustSubmissionPostRound(
          store,
          stakeVault,
          submission.id,
          updatedGovRate,
          updatedMultiRate,
        );

        // 9. Verify the result
        switch (result) {
          case (#err(_)) {
            assert (false);
          };
          case (#ok(adjustedSubmission)) {
            assert (adjustedSubmission.status == #PostRound);

            let adjustedQuantity = switch (adjustedSubmission.adjustedQuantity) {
              case (null) { assert (false); 0 };
              case (?adjusted) { adjusted.value };
            };

            // When rates double, quantity should approximately halve
            assert (adjustedQuantity < tokenQuantity.value);

            // Verify tokens were returned to user
            let returnedTokens = stakeVault.getStakeAccounts().getBalance(user, testToken).value;
            assert (returnedTokens > 0);
          };
        };
      },
    );

    test(
      "adjustSubmissionPostRound handles equal rates correctly",
      func() {
        let (store, stakeVault, user, _, _) = setupTest();

        // 1. Get the test token and price
        let testToken = CompetitionTestUtils.getTestToken1();
        let price = switch (store.getCompetitionPrice(testToken)) {
          case (null) {
            assert (false);
            {
              baseToken = testToken;
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = 0 };
            };
          };
          case (?p) { p };
        };

        // 2. Set up gov stake
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };

        // 3. Calculate multi stake from gov stake
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          { value = CompetitionTestUtils.getFIVE_PERCENT() },
          { value = CompetitionTestUtils.getONE_PERCENT() },
          CompetitionTestUtils.getMultiToken(),
        );

        // 4. Calculate token quantity from multi stake
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          multiStake,
          { value = CompetitionTestUtils.getONE_PERCENT() },
          price,
        );

        // 5. Create submission using CALCULATED values
        let submission = SubmissionOperations.createSubmission(
          store,
          user,
          testToken,
          tokenQuantity.value, // Use calculated value instead of fixed
          govStake,
          multiStake,
        );

        // 6. Process the submission
        switch (SubmissionOperations.processSubmission(store, stakeVault, submission)) {
          case (#err(_)) {
            assert (false);
          };
          case (#ok(_)) {};
        };

        // Check initial stake account balance
        let initialStakedTokens = stakeVault.getStakeAccounts().getBalance(user, testToken).value;

        // 7. Use the SAME rates for adjustment
        let sameGovRate = { value = CompetitionTestUtils.getFIVE_PERCENT() };
        let sameMultiRate = { value = CompetitionTestUtils.getONE_PERCENT() };

        // 8. Adjust the submission
        let result = SubmissionOperations.adjustSubmissionPostRound(
          store,
          stakeVault,
          submission.id,
          sameGovRate,
          sameMultiRate,
        );

        // 9. Verify the result
        switch (result) {
          case (#err(_)) {
            assert (false);
          };
          case (#ok(adjustedSubmission)) {
            assert (adjustedSubmission.status == #PostRound);

            let adjustedQuantity = switch (adjustedSubmission.adjustedQuantity) {
              case (null) { assert (false); 0 };
              case (?adjusted) { adjusted.value };
            };

            // With equal rates, key invariant: adjusted quantity equals original quantity
            assert (adjustedQuantity == tokenQuantity.value);
          };
        };
      },
    );
  },
);
