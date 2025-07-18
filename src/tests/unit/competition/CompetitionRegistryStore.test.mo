import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import { suite; test; expect } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionRegistryTypes "../../../multi_backend/types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import RewardTypes "../../../multi_backend/types/RewardTypes";
import CompetitionRegistryStore "../../../multi_backend/competition/CompetitionRegistryStore";
import CompetitionTestUtils "./CompetitionTestUtils";

// Test suite for the CompetitionRegistryStore
suite(
  "Competition Registry Store",
  func() {
    // Create test data using functions from CompetitionTestUtils
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockTokenB = CompetitionTestUtils.getTestToken2();

    test(
      "initializes registry correctly",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();

        // Verify initialization
        expect.bool(registry.hasInitialized()).isTrue();
        expect.bool(registry.hasActiveCompetition()).isFalse();

        // Get global config
        let config = registry.getGlobalConfig();
        expect.principal(config.govToken).equal(mockGovToken);
        expect.principal(config.multiToken).equal(mockSystemToken);
        expect.nat(config.approvedTokens.size()).equal(3); // From test utils
      },
    );

    test(
      "creates and manages competitions correctly",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();

        // Initially no active competition
        expect.bool(registry.hasActiveCompetition()).isFalse();

        // Check that current competition is null
        switch (registry.getCurrentCompetition()) {
          case (null) {
            // Expected, continue test
          };
          case (_) {
            expect.bool(false).isTrue(); // Should be null initially
          };
        };

        // Create a new competition
        let result = registry.createCompetition();

        switch (result) {
          case (#err(e)) {
            expect.bool(false).isTrue(); // Should not error
          };
          case (#ok(competitionId)) {
            // Check competition was created and is active
            expect.bool(registry.hasActiveCompetition()).isTrue();

            // FIXED: getCurrentCompetitionId now returns the NEXT competition ID after increment
            // The created competition has ID = competitionId
            // After creation, currentCompetitionId is incremented to competitionId + 1
            expect.nat(registry.getCurrentCompetitionId()).equal(competitionId + 1);

            // Get competition entry
            switch (registry.getCurrentCompetition()) {
              case (null) {
                expect.bool(false).isTrue(); // Should not be null
              };
              case (?competition) {
                expect.nat(competition.id).equal(competitionId);
                expect.bool(competition.status == #PreAnnouncement).isTrue();
              };
            };

            // Get competition entry store
            switch (registry.getCurrentCompetitionEntryStore()) {
              case (null) {
                expect.bool(false).isTrue(); // Should not be null
              };
              case (?entryStore) {
                expect.bool(entryStore.getStatus() == #PreAnnouncement).isTrue();
                expect.nat(entryStore.getId()).equal(competitionId);
              };
            };
          };
        };
      },
    );

    test(
      "handles competition state transitions correctly",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();

        // Create a competition
        switch (registry.createCompetition()) {
          case (#err(_)) {
            expect.bool(false).isTrue(); // Should not error
          };
          case (#ok(_)) {
            // Get the entry store to change status
            switch (registry.getCurrentCompetitionEntryStore()) {
              case (null) {
                expect.bool(false).isTrue(); // Should not be null
              };
              case (?entryStore) {
                // Test transition to AcceptingStakes
                entryStore.updateStatus(#AcceptingStakes);
                expect.bool(registry.hasActiveCompetition()).isTrue();

                // Test transition to Finalizing
                entryStore.updateStatus(#Finalizing);
                expect.bool(registry.hasActiveCompetition()).isTrue();

                // Test transition to Settlement
                entryStore.updateStatus(#Settlement);
                expect.bool(registry.hasActiveCompetition()).isTrue();

                // Test transition to Distribution - should clear active ID
                entryStore.updateStatus(#Distribution);
                expect.bool(registry.hasActiveCompetition()).isFalse();

                // Get competition by ID to verify it still exists in registry
                let competitions = registry.getGlobalCompetitions();
                expect.nat(competitions.size()).equal(1);
                expect.bool(competitions[0].status == #Distribution).isTrue();
              };
            };
          };
        };
      },
    );

    test(
      "checks token approval correctly",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();

        // Check approved tokens
        expect.bool(registry.isTokenApproved(mockTokenA)).isTrue();
        expect.bool(registry.isTokenApproved(mockTokenB)).isTrue();

        // Check unapproved token
        let unapprovedToken = Principal.fromText("aaaaa-aa");
        expect.bool(registry.isTokenApproved(unapprovedToken)).isFalse();
      },
    );

    test(
      "retrieves competition prices correctly",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();

        // Get price for an approved token
        switch (registry.getCompetitionPrice(mockTokenA)) {
          case (null) {
            expect.bool(false).isTrue(); // Should not be null
          };
          case (?price) {
            expect.principal(price.baseToken).equal(mockTokenA);
            expect.principal(price.quoteToken).equal(mockSystemToken);
          };
        };

        // Get price for an unapproved token
        let unapprovedToken = Principal.fromText("aaaaa-aa");
        switch (registry.getCompetitionPrice(unapprovedToken)) {
          case (null) {
            // Expected, continue test
          };
          case (_) {
            expect.bool(false).isTrue(); // Should be null
          };
        };
      },
    );

    test(
      "retrieves non-active competition entry stores by ID",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();
        var competitionId : Nat = 0;

        // Create a new competition
        switch (registry.createCompetition()) {
          case (#err(_)) {
            expect.bool(false).isTrue(); // Should not error
          };
          case (#ok(id)) {
            competitionId := id;

            // Get the entry store and move it to Distribution status
            switch (registry.getCurrentCompetitionEntryStore()) {
              case (null) {
                expect.bool(false).isTrue(); // Should not be null
              };
              case (?entryStore) {
                // Test transition directly to Distribution
                entryStore.updateStatus(#Distribution);

                // Verify the competition is no longer active
                expect.bool(registry.hasActiveCompetition()).isFalse();

                // Now try to get the same competition using getCompetitionEntryStoreById
                switch (registry.getCompetitionEntryStoreById(competitionId)) {
                  case (null) {
                    expect.bool(false).isTrue(); // Should not be null - we should be able to get non-active competitions
                  };
                  case (?retrievedEntryStore) {
                    // Verify we got the right competition
                    expect.nat(retrievedEntryStore.getId()).equal(competitionId);
                    expect.bool(retrievedEntryStore.getStatus() == #Distribution).isTrue();

                    // Test that we can still interact with the non-active competition
                    let initialStatus = retrievedEntryStore.getStatus();
                    retrievedEntryStore.updateStatus(#Completed);

                    // Verify the status was updated
                    expect.bool(retrievedEntryStore.getStatus() == #Completed).isTrue();

                    // Get the competition directly from global competitions to verify
                    let competitions = registry.getGlobalCompetitions();
                    expect.nat(competitions.size()).equal(1);
                    expect.bool(competitions[0].status == #Completed).isTrue();
                  };
                };
              };
            };
          };
        };

        // Test non-existent competition ID
        let nonExistentId = competitionId + 100;
        switch (registry.getCompetitionEntryStoreById(nonExistentId)) {
          case (null) {
            // Expected, this ID doesn't exist
          };
          case (_) {
            expect.bool(false).isTrue(); // Should be null for non-existent ID
          };
        };
      },
    );

    test(
      "navigates the competition-position hierarchy",
      func() {
        let registry = CompetitionTestUtils.createCompetitionRegistryStore();
        var competitionId : Nat = 0;

        // 1. Create a competition
        switch (registry.createCompetition()) {
          case (#err(_)) {
            expect.bool(false).isTrue(); // Should not error
          };
          case (#ok(id)) {
            competitionId := id;

            // 2. Get the competition entry store
            switch (registry.getCompetitionEntryStoreById(competitionId)) {
              case (null) {
                expect.bool(false).isTrue(); // Should not be null
              };
              case (?entryStore) {
                // 3. Create a test position
                let testToken = CompetitionTestUtils.getTestToken1();
                let position : RewardTypes.Position = {
                  quantity = { token = testToken; value = 1000 };
                  govStake = { token = mockGovToken; value = 200 };
                  multiStake = { token = mockSystemToken; value = 100 };
                  submissionId = ?0;
                  isSystem = false;
                  distributionPayouts = [];
                };

                // 4. Add the position to the competition
                entryStore.addPosition(position);

                // 5. Verify the position was added
                let positions = entryStore.getPositions();
                expect.nat(positions.size()).equal(1);

                // 6. For now, positions don't have performance history
                // This will need to be addressed when we properly implement performance tracking

                // 7. Get the competition again to verify persistence
                switch (registry.getCompetitionEntryStoreById(competitionId)) {
                  case (null) {
                    expect.bool(false).isTrue(); // Should not be null
                  };
                  case (?refreshedStore) {
                    // 8. Verify we can access the positions
                    let refreshedPositions = refreshedStore.getPositions();
                    expect.nat(refreshedPositions.size()).equal(1);

                    // 9. Verify the position data
                    let pos = refreshedPositions[0];
                    expect.nat(pos.quantity.value).equal(1000);
                    expect.nat(pos.govStake.value).equal(200);
                    expect.nat(pos.multiStake.value).equal(100);
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
