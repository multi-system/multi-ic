import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import { suite; test; expect } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionRegistryTypes "../../../multi_backend/types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import StakeTokenTypes "../../../multi_backend/types/StakeTokenTypes";
import CompetitionUserOperations "../../../multi_backend/competition/CompetitionUserOperations";
import CompetitionRegistryStore "../../../multi_backend/competition/CompetitionRegistryStore";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import CompetitionTestUtils "./CompetitionTestUtils";

import RatioOperations "../../../multi_backend/financial/RatioOperations";

// Test suite for CompetitionUserOperations
suite(
  "Competition User Operations",
  func() {
    // Create mock tokens for testing
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockUser = CompetitionTestUtils.getUserPrincipal();

    // Helper function to create test environment with registry store
    func createTestEnvironmentWithRegistry() : (
      CompetitionRegistryStore.CompetitionRegistryStore,
      VirtualAccounts.VirtualAccounts,
      Types.Account,
      () -> Nat,
      () -> [BackingTypes.BackingPair],
    ) {
      // Create base test environment
      let (entryStore, _, userAccount, getCirculatingSupply, getBackingTokens, _) = CompetitionTestUtils.createTestEnvironment();

      // Create user accounts separately
      let userAccounts = CompetitionTestUtils.createUserAccounts();

      // Get the competition data and create a new one with PreAnnouncement status
      let originalData = entryStore.getData();
      let competitionData = {
        originalData with status = #PreAnnouncement
      };

      // Create registry state
      let registryState : CompetitionRegistryTypes.CompetitionRegistryState = {
        var globalConfig = {
          multiToken = mockSystemToken;
          approvedTokens = [mockTokenA];
          theta = { value = CompetitionTestUtils.getFIVE_PERCENT() };
          stakeTokenConfigs = CompetitionTestUtils.createDefaultStakeTokenConfigs();
          competitionCycleDuration = 86_400_000_000_000;
          preAnnouncementDuration = 3_600_000_000_000;
          rewardDistributionDuration = 7_200_000_000_000;
          numberOfDistributionEvents = 3;
        };
        var competitions = [competitionData]; // Use the modified competition data
        var currentCompetitionId = 1;
        var hasInitialized = true;
        var startTime = 0;
        var eventRegistry = CompetitionTestUtils.createTestEventRegistry();
      };

      // Create registry store
      let registryStore = CompetitionRegistryStore.CompetitionRegistryStore(
        registryState,
        userAccounts,
      );

      (registryStore, userAccounts, userAccount, getCirculatingSupply, getBackingTokens);
    };

    test(
      "accepts stake request successfully",
      func() {
        // Create test environment with registry
        let (registryStore, userAccounts, userAccount, getCirculatingSupply, getBackingTokens) = createTestEnvironmentWithRegistry();

        // Get the entry store and update status to AcceptingStakes
        switch (registryStore.getCurrentCompetitionEntryStore()) {
          case (null) {
            Debug.print("No current competition found");
            expect.bool(false).isTrue();
          };
          case (?entryStore) {
            entryStore.updateStatus(#AcceptingStakes);
          };
        };

        // Create the user operations instance
        let userOps = CompetitionUserOperations.CompetitionUserOperations(
          registryStore,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Test accepting a stake request
        let result = userOps.acceptStakeRequest(
          govStake,
          userAccount,
          mockTokenA,
        );

        // Verify results
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Force test failure
          };
          case (#ok(data)) {
            expect.principal(data.tokenQuantity.token).equal(mockTokenA);
            expect.nat(data.submissionId).equal(0); // In our test env, first ID is 0
          };
        };
      },
    );

    test(
      "fails to accept stake when competition is in wrong state",
      func() {
        // Create test environment with registry
        let (registryStore, userAccounts, userAccount, getCirculatingSupply, getBackingTokens) = createTestEnvironmentWithRegistry();

        // Competition should already be in PreAnnouncement state from helper function
        // Let's verify this
        switch (registryStore.getCurrentCompetitionEntryStore()) {
          case (null) {
            Debug.print("No competition found in test");
          };
          case (?entryStore) {
            Debug.print("Competition status before test: " # debug_show (entryStore.getStatus()));
          };
        };

        // Create the user operations instance
        let userOps = CompetitionUserOperations.CompetitionUserOperations(
          registryStore,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Test accepting a stake request (should fail)
        let result = userOps.acceptStakeRequest(
          govStake,
          userAccount,
          mockTokenA,
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
      "fails when no competition is active",
      func() {
        // Create user accounts
        let userAccounts = CompetitionTestUtils.createUserAccounts();

        // Create a registry with no competitions
        let registryState : CompetitionRegistryTypes.CompetitionRegistryState = {
          var globalConfig = {
            multiToken = mockSystemToken;
            approvedTokens = [mockTokenA];
            theta = { value = CompetitionTestUtils.getFIVE_PERCENT() };
            stakeTokenConfigs = CompetitionTestUtils.createDefaultStakeTokenConfigs();
            competitionCycleDuration = 86_400_000_000_000;
            preAnnouncementDuration = 3_600_000_000_000;
            rewardDistributionDuration = 7_200_000_000_000;
            numberOfDistributionEvents = 3;
          };
          var competitions = []; // No competitions
          var currentCompetitionId = 0;
          var hasInitialized = true;
          var startTime = 0;
          var eventRegistry = CompetitionTestUtils.createTestEventRegistry();
        };

        let registryStore = CompetitionRegistryStore.CompetitionRegistryStore(
          registryState,
          userAccounts,
        );

        let getCirculatingSupply = func() : Nat { 1_000_000 };
        let getBackingTokens = func() : [BackingTypes.BackingPair] { [] };

        // Create the user operations instance
        let userOps = CompetitionUserOperations.CompetitionUserOperations(
          registryStore,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Create test governance stake
        let govStake : Types.Amount = {
          token = mockGovToken;
          value = 1000;
        };

        // Test accepting a stake request (should fail with CompetitionNotActive)
        let result = userOps.acceptStakeRequest(
          govStake,
          mockUser, // Using the principal directly as account
          mockTokenA,
        );

        // Verify results
        switch (result) {
          case (#err(#CompetitionNotActive)) {
            // Expected error
          };
          case (_) {
            Debug.print("Expected CompetitionNotActive error but got: " # debug_show (result));
            expect.bool(false).isTrue(); // Force test failure
          };
        };
      },
    );

    test(
      "accepts and processes stake requests immediately",
      func() {
        // Create test environment with registry
        let (registryStore, userAccounts, userAccount, getCirculatingSupply, getBackingTokens) = createTestEnvironmentWithRegistry();

        // Create the user operations instance
        let userOps = CompetitionUserOperations.CompetitionUserOperations(
          registryStore,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Get the entry store BEFORE making the request
        let entryStoreOpt = registryStore.getCurrentCompetitionEntryStore();
        switch (entryStoreOpt) {
          case (null) {
            Debug.print("No current competition found");
            expect.bool(false).isTrue();
          };
          case (?entryStore) {
            // First update status to AcceptingStakes
            entryStore.updateStatus(#AcceptingStakes);

            // Create test governance stake
            let govStake : Types.Amount = {
              token = mockGovToken;
              value = 1000;
            };

            // Submit a stake request - now processed immediately
            let result = userOps.acceptStakeRequest(
              govStake,
              userAccount,
              mockTokenA,
            );

            // Verify results
            switch (result) {
              case (#err(e)) {
                Debug.print("Unexpected error: " # debug_show (e));
                expect.bool(false).isTrue(); // Force test failure
              };
              case (#ok(data)) {
                expect.principal(data.tokenQuantity.token).equal(mockTokenA);

                // Get a fresh entry store to check submissions
                // This ensures we're looking at the updated data
                switch (registryStore.getCurrentCompetitionEntryStore()) {
                  case (null) {
                    Debug.print("No competition found after submission");
                    expect.bool(false).isTrue();
                  };
                  case (?freshEntryStore) {
                    // Verify the submission was added with Staked status
                    let stakedSubmissions = freshEntryStore.getSubmissionsByStatus(#Staked);
                    Debug.print("Number of staked submissions: " # Nat.toText(stakedSubmissions.size()));

                    // Also check all submissions
                    let allSubmissions = freshEntryStore.getAllSubmissions();
                    Debug.print("Total submissions: " # Nat.toText(allSubmissions.size()));
                    for (sub in allSubmissions.vals()) {
                      Debug.print("Submission " # Nat.toText(sub.id) # " status: " # debug_show (sub.status));
                    };

                    expect.nat(stakedSubmissions.size()).equal(1);

                    // Verify the submission has the expected properties
                    let submission = stakedSubmissions[0];
                    expect.nat(submission.id).equal(data.submissionId);
                    expect.principal(submission.token).equal(mockTokenA);
                    expect.bool(submission.status == #Staked).isTrue();
                  };
                };
              };
            };
          };
        };
      },
    );
  },
);
