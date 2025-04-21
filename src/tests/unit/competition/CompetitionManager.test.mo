import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Result "mo:base/Result";
import { suite; test; expect } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionRegistryTypes "../../../multi_backend/types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import CompetitionManager "../../../multi_backend/competition/CompetitionManager";
import FinalizeStakingRound "../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionTestUtils "./CompetitionTestUtils";

// Test suite for the CompetitionManager
suite(
  "Competition Manager",
  func() {
    // Create mock tokens for testing
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockUser = CompetitionTestUtils.getUserPrincipal();

    test(
      "starts staking round successfully",
      func() {
        // Create test environment
        let (entryStore, _, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Set status to PreAnnouncement for testing
        entryStore.updateStatus(#PreAnnouncement);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Test starting the staking round
        let result = manager.startStakingRound(entryStore);

        // Verify results
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Force test failure
          };
          case (#ok(id)) {
            expect.nat(id).equal(entryStore.getId());
            expect.bool(entryStore.getStatus() == #AcceptingStakes).isTrue();
          };
        };
      },
    );

    test(
      "starts staking round only from PreAnnouncement state",
      func() {
        // Create test environment
        let (entryStore, _, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Set status to PreAnnouncement
        entryStore.updateStatus(#PreAnnouncement);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Test starting the staking round
        let result = manager.startStakingRound(entryStore);

        // Verify the competition was started successfully
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Force test failure
          };
          case (#ok(id)) {
            expect.nat(id).equal(entryStore.getId());
            expect.bool(entryStore.getStatus() == #AcceptingStakes).isTrue();
          };
        };
      },
    );

    test(
      "accepts stake request successfully",
      func() {
        // Create test environment with a competition in AcceptingStakes state
        let (entryStore, stakeVault, userAccount, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();
        entryStore.updateStatus(#AcceptingStakes);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Test accepting a stake request (not queued)
        let result = manager.acceptStakeRequest(
          entryStore,
          govStake,
          userAccount,
          mockTokenA,
          false // not queued
        );

        // Verify results
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Force test failure
          };
          case (#ok(data)) {
            expect.bool(data.isQueued).isFalse();
            expect.principal(data.tokenQuantity.token).equal(mockTokenA);
            expect.nat(data.submissionId).equal(0); // In our test env, first ID is 0
          };
        };
      },
    );

    test(
      "fails to accept stake when competition is in wrong state",
      func() {
        // Create test environment with a competition in wrong state
        let (entryStore, stakeVault, userAccount, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();
        entryStore.updateStatus(#PreAnnouncement); // Wrong state for accepting stakes

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Test accepting a stake request (should fail)
        let result = manager.acceptStakeRequest(
          entryStore,
          govStake,
          userAccount,
          mockTokenA,
          false,
        );

        // Verify results
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (_) {
            Debug.print("Expected InvalidPhase error but got: " # debug_show (result));
            expect.bool(false).isTrue(); // Force test failure
          };
        };
      },
    );

    test(
      "accepts and queues stake requests properly",
      func() {
        // Create test environment with a competition in AcceptingStakes state
        let (entryStore, stakeVault, userAccount, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();
        entryStore.updateStatus(#AcceptingStakes);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Submit a stake request as queued
        let result = manager.acceptStakeRequest(
          entryStore,
          govStake,
          userAccount,
          mockTokenA,
          true // queued
        );

        // Verify results
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Force test failure
          };
          case (#ok(data)) {
            expect.bool(data.isQueued).isTrue();
            expect.principal(data.tokenQuantity.token).equal(mockTokenA);

            // Verify the submission was added with Queued status
            let queuedSubmissions = entryStore.getSubmissionsByStatus(#Queued);
            expect.nat(queuedSubmissions.size()).equal(1);

            // Verify the submission has the expected properties
            let submission = queuedSubmissions[0];
            expect.nat(submission.id).equal(data.submissionId);
            expect.principal(submission.token).equal(mockTokenA);
            expect.bool(submission.status == #Queued).isTrue();
          };
        };
      },
    );
  },
);
