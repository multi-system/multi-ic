import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import FinalizeStakingRound "../../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import StakeCalculator "../../../../multi_backend/competition/staking/StakeCalculator";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "FinalizeStakingRound Tests",
  func() {
    // Setup helper to create test environment with realistic active submissions
    func setupWithActiveSubmissions(
      activeCount : Nat
    ) : (
      CompetitionEntryStore.CompetitionEntryStore,
      Types.Account,
      () -> Nat,
      () -> [BackingTypes.BackingPair],
    ) {
      let (competitionEntry, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

      // Ensure competition is active
      competitionEntry.updateStatus(#AcceptingStakes);

      // Create and add active round submissions with realistic values
      for (_ in Iter.range(0, activeCount - 1)) {
        let id = competitionEntry.generateSubmissionId();

        // Get current rates
        let govRate = competitionEntry.getAdjustedGovRate();
        let multiRate = competitionEntry.getAdjustedMultiRate();

        // Standard stake amounts
        let govStake = {
          token = CompetitionTestUtils.getGovToken();
          value = 5_000;
        };

        // Calculate proper multi stake based on gov stake
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          govRate,
          multiRate,
          CompetitionTestUtils.getMultiToken(),
        );

        // Get test token price
        let tokenPrice = {
          baseToken = CompetitionTestUtils.getTestToken1();
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
        };

        // Calculate realistic token quantity
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          multiStake,
          multiRate,
          tokenPrice,
        );

        // Create submission with proper values
        let submission : SubmissionTypes.Submission = {
          id = id;
          participant = user;
          // Use calculated values
          govStake = govStake;
          multiStake = multiStake;
          // Token information
          token = CompetitionTestUtils.getTestToken1();
          // Initial submission with properly calculated quantity
          proposedQuantity = tokenQuantity;
          timestamp = Time.now();
          // Current state
          status = #Staked;
          rejectionReason = null;
          // Adjustment results
          adjustedQuantity = null;
          // Settlement results
          soldQuantity = null;
          executionPrice = null;
          // Position reference
          positionId = null;
        };

        // Add tokens to stake vault for this submission
        competitionEntry.getStakeVault().stake(user, submission.govStake);
        competitionEntry.getStakeVault().stake(user, submission.multiStake);
        competitionEntry.getStakeVault().stake(user, submission.proposedQuantity);

        // Add submission to competition entry
        competitionEntry.addSubmission(submission);
      };

      (competitionEntry, user, getCirculatingSupply, getBackingTokens);
    };

    test(
      "finalizeRound - basic successful finalization",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(2);

        // Execute finalization - note the updated parameter order
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // Check counts
            assert finalization.stakedSubmissionsCount == 2;

            // Verify that rates didn't change (since we didn't set high stakes)
            assert finalization.initialGovRate.value == finalization.finalGovRate.value;
            assert finalization.initialMultiRate.value == finalization.finalMultiRate.value;

            // Verify all submissions moved to Finalized status
            let finalizedSubmissions = competitionEntry.getSubmissionsByStatus(#Finalized);
            assert finalizedSubmissions.size() == 2;
          };
        };
      },
    );

    test(
      "finalizeRound - with empty submission list",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(0); // No submissions

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail even with empty list
          };
          case (#ok(finalization)) {
            // Check counts
            assert finalization.stakedSubmissionsCount == 0;
            assert finalization.queuedProcessedCount == 0;
            assert finalization.adjustmentSuccessCount == 0;

            // System stake should still be calculated
            assert finalization.systemStake.phantomPositions.size() >= 0;
          };
        };
      },
    );

    test(
      "finalizeRound - when competition not active",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Set competition to inactive
        competitionEntry.updateStatus(#PreAnnouncement);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (#err(_)) {
            assert false; // Should only get InvalidPhase error
          };
          case (#ok(_)) {
            assert false; // Should not succeed when competition is inactive
          };
        };
      },
    );

    test(
      "finalizeRound - when system not initialized",
      func() {
        // Create an uninitialized competition entry store for testing
        let (competitionEntry, _, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(0);

        // Update status to inactive to simulate uninitialized state
        competitionEntry.updateStatus(#PreAnnouncement);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#InvalidPhase(_)) or #err(#OperationFailed(_))) {
            // Expected error
          };
          case (#err(_)) {
            assert false; // Should only get expected error types
          };
          case (#ok(_)) {
            assert false; // Should not succeed when system is not initialized
          };
        };
      },
    );

    test(
      "finalizeRound - stake rates adjustment logic",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(3);

        // Get initial rates before update
        let initialGovRate = competitionEntry.getAdjustedGovRate();
        let initialMultiRate = competitionEntry.getAdjustedMultiRate();

        // Set large stakes to force rate adjustment - should be higher than initial rates
        competitionEntry.updateTotalStakes(500_000, 200_000);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // Check rates increased for at least one token type
            assert finalization.finalGovRate.value >= finalization.initialGovRate.value;
            assert finalization.finalMultiRate.value >= finalization.initialMultiRate.value;
            assert finalization.finalGovRate.value > finalization.initialGovRate.value or finalization.finalMultiRate.value > finalization.initialMultiRate.value;
          };
        };
      },
    );

    test(
      "finalizeRound - system stake calculation verification",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // Check system stake properties
            assert finalization.systemStake.govSystemStake.token == CompetitionTestUtils.getGovToken();
            assert finalization.systemStake.multiSystemStake.token == CompetitionTestUtils.getMultiToken();

            // Verify phantom positions
            assert finalization.systemStake.phantomPositions.size() > 0;

            // If we have phantom positions, verify first one's token type
            if (finalization.systemStake.phantomPositions.size() > 0) {
              let (phantomToken, _) = finalization.systemStake.phantomPositions[0];
              // It should be one of our test tokens
              assert Principal.equal(phantomToken, CompetitionTestUtils.getTestToken1()) or Principal.equal(phantomToken, CompetitionTestUtils.getTestToken2()) or Principal.equal(phantomToken, CompetitionTestUtils.getTestToken3());
            };
          };
        };
      },
    );
  },
);
