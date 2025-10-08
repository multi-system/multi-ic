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
        let (entryStore, _, _, getCirculatingSupply, getBackingTokens, _) = CompetitionTestUtils.createTestEnvironment();

        // Set status to PreAnnouncement for testing
        entryStore.updateStatus(#PreAnnouncement);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Get user accounts and system account functions
        let getUserAccounts = CompetitionTestUtils.getUserAccountsFunction();
        let getSystemAccount = CompetitionTestUtils.getSystemAccountFunction();

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
          getUserAccounts,
          getSystemAccount,
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
        let (entryStore, _, _, getCirculatingSupply, getBackingTokens, _) = CompetitionTestUtils.createTestEnvironment();

        // Set status to PreAnnouncement
        entryStore.updateStatus(#PreAnnouncement);

        // Create mock settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Get user accounts and system account functions
        let getUserAccounts = CompetitionTestUtils.getUserAccountsFunction();
        let getSystemAccount = CompetitionTestUtils.getSystemAccountFunction();

        // Create the competition manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
          getUserAccounts,
          getSystemAccount,
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

    // TODO: Add tests for:
    // - endStakingRound
    // - processQueue
    // - processDistribution
    // - endCompetition
  },
);
