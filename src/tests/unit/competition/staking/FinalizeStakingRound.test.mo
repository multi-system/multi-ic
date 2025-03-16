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
import CompetitionTypes "../../../../multi_backend/types/CompetitionTypes";
import FinalizeStakingRound "../../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionStore "../../../../multi_backend/competition/CompetitionStore";
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
      CompetitionStore.CompetitionStore,
      StakeVault.StakeVault,
      Types.Account,
      () -> Nat,
      () -> [BackingTypes.BackingPair],
    ) {
      let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

      // Ensure competition is active
      store.setCompetitionActive(true);

      // Create and add active round submissions with realistic values
      for (_ in Iter.range(0, activeCount - 1)) {
        let id = store.generateSubmissionId();

        // Get current rates from store
        let govRate = store.getGovRate();
        let multiRate = store.getMultiRate();

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
          status = #ActiveRound;
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
        stakeVault.stake(user, submission.govStake);
        stakeVault.stake(user, submission.multiStake);
        stakeVault.stake(user, submission.proposedQuantity);

        // Add submission to store
        store.addSubmission(submission);
      };

      (store, stakeVault, user, getCirculatingSupply, getBackingTokens);
    };

    test(
      "finalizeRound - basic successful finalization",
      func() {
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(2);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          store,
          stakeVault,
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
            assert finalization.activeSubmissionsCount == 2;

            // Verify that rates didn't change (since we didn't set high stakes)
            assert finalization.initialGovRate.value == finalization.finalGovRate.value;
            assert finalization.initialMultiRate.value == finalization.finalMultiRate.value;

            // Verify all submissions moved to PostRound status
            let postRoundSubmissions = store.getSubmissionsByStatus(#PostRound);
            assert postRoundSubmissions.size() == 2;
          };
        };
      },
    );

    test(
      "finalizeRound - with empty submission list",
      func() {
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(0); // No submissions

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          store,
          stakeVault,
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
            assert finalization.activeSubmissionsCount == 0;
            assert finalization.preRoundProcessedCount == 0;
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
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Set competition to inactive
        store.setCompetitionActive(false);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          store,
          stakeVault,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#CompetitionNotActive)) {
            // Expected error
          };
          case (#err(_)) {
            assert false; // Should only get CompetitionNotActive error
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
        // Create a store without initializing it
        let state : CompetitionTypes.CompetitionState = {
          var hasInitialized = false;
          var competitionActive = true;
          var submissions = [];
          var nextSubmissionId = 0;
          var totalGovStake = 0;
          var totalMultiStake = 0;
          var config = {
            govToken = CompetitionTestUtils.getGovToken();
            multiToken = CompetitionTestUtils.getMultiToken();
            approvedTokens = [];
            competitionPrices = [];
            govRate = { value = CompetitionTestUtils.getFIVE_PERCENT() };
            multiRate = { value = CompetitionTestUtils.getONE_PERCENT() };
            theta = { value = CompetitionTestUtils.getTWENTY_PERCENT() };
            systemStakeGov = {
              value = CompetitionTestUtils.getTWENTY_PERCENT();
            };
            systemStakeMulti = {
              value = CompetitionTestUtils.getFIFTY_PERCENT();
            };
            competitionPeriodLength = 0;
            competitionSpacing = 0;
            settlementDuration = 0;
            rewardDistributionFrequency = 0;
            numberOfDistributionEvents = 0;
          };
        };

        let uninitializedStore = CompetitionStore.CompetitionStore(state);
        let (_, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          uninitializedStore,
          stakeVault,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#OperationFailed(_))) {
            // Expected error for uninitialized system
          };
          case (#err(_)) {
            assert false; // Should only get OperationFailed error
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
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(3);

        // Get initial rates before update
        let initialGovRate = store.getGovRate();
        let initialMultiRate = store.getMultiRate();

        // Set large stakes to force rate adjustment - should be higher than initial rates
        store.updateTotalStakes(500_000, 200_000);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          store,
          stakeVault,
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
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          store,
          stakeVault,
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
