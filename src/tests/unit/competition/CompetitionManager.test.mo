import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import { test; suite } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import SystemStakeTypes "../../../multi_backend/types/SystemStakeTypes";
import CompetitionStore "../../../multi_backend/competition/CompetitionStore";
import StakeVault "../../../multi_backend/competition/staking/StakeVault";
import CompetitionManager "../../../multi_backend/competition/CompetitionManager";
import FinalizeStakingRound "../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionTestUtils "./CompetitionTestUtils";

suite(
  "CompetitionManager Tests",
  func() {
    // Setup helper to create test environment for manager tests
    func setupManagerTest() : (
      CompetitionManager.CompetitionManager,
      CompetitionStore.CompetitionStore,
      StakeVault.StakeVault,
      Types.Account,
    ) {
      let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

      // Create a test CompetitionManager
      let manager = CompetitionManager.CompetitionManager(
        store,
        stakeVault,
        getCirculatingSupply,
        getBackingTokens,
        null, // No settlement initiator for basic tests
      );

      (manager, store, stakeVault, user);
    };

    test(
      "startStakingRound - starts round when inactive",
      func() {
        let (manager, store, _, _) = setupManagerTest();

        // Ensure competition is inactive
        store.setCompetitionActive(false);

        // Start staking round
        let result = manager.startStakingRound();

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(_)) {
            // Verify competition is now active
            assert store.isCompetitionActive();
          };
        };
      },
    );

    test(
      "startStakingRound - fails when already active",
      func() {
        let (manager, store, _, _) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Try to start again
        let result = manager.startStakingRound();

        // Verify error
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(_)) {
            Debug.print("Should have failed due to active competition");
            assert false;
          };
        };
      },
    );

    test(
      "acceptStakeRequest - processes request successfully",
      func() {
        let (manager, store, _, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Create stake request
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();
        let shouldQueue = false; // Process immediately

        // Submit stake request
        let result = manager.acceptStakeRequest(
          govStake,
          user,
          testToken,
          shouldQueue,
        );

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(output)) {
            assert output.submissionId == 0; // First submission
            assert output.isQueued == false; // Not queued
            assert output.tokenQuantity.value > 0; // Some tokens calculated
          };
        };
      },
    );

    test(
      "endStakingRound - finalizes and transitions state correctly",
      func() {
        let (manager, store, stakeVault, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Add a test submission to ensure there's something to finalize
        let id = store.generateSubmissionId();

        // Create a properly calculated submission with status ActiveRound
        let submission : SubmissionTypes.Submission = {
          id = id;
          participant = user;
          govStake = {
            token = CompetitionTestUtils.getGovToken();
            value = 5_000;
          };
          multiStake = {
            token = CompetitionTestUtils.getMultiToken();
            value = 1_000;
          };
          token = CompetitionTestUtils.getTestToken1();
          proposedQuantity = {
            token = CompetitionTestUtils.getTestToken1();
            value = 100_000;
          };
          timestamp = Time.now();
          status = #ActiveRound;
          rejectionReason = null;
          adjustedQuantity = null;
          soldQuantity = null;
          executionPrice = null;
          positionId = null;
        };

        // Add tokens to stake vault
        stakeVault.stake(user, submission.govStake);
        stakeVault.stake(user, submission.multiStake);
        stakeVault.stake(user, submission.proposedQuantity);

        // Add submission to store
        store.addSubmission(submission);

        // End staking round
        let result = manager.endStakingRound();

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(finalization)) {
            // Check competition is inactive
            assert (not store.isCompetitionActive());

            // Check submission is now PostRound - a key whitepaper requirement
            let postRoundSubmissions = store.getSubmissionsByStatus(#PostRound);
            assert (postRoundSubmissions.size() > 0);
          };
        };
      },
    );

    test(
      "getQueuedSubmissions - returns correct submissions",
      func() {
        let (manager, store, _, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Create and queue submissions
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };

        // Queue two submissions
        ignore manager.acceptStakeRequest(
          govStake,
          user,
          CompetitionTestUtils.getTestToken1(),
          true,
        );

        ignore manager.acceptStakeRequest(
          govStake,
          user,
          CompetitionTestUtils.getTestToken2(),
          true,
        );

        // Get queued submissions
        let queuedSubmissions = manager.getQueuedSubmissions();

        // Verify queue state
        assert queuedSubmissions.size() == 2;
        assert manager.getQueueSize() == 2;
      },
    );
  },
);
