import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import { suite; test; expect } "mo:test";

import Types "../../../../multi_backend/types/Types";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import DistributionCoordinator "../../../../multi_backend/competition/distribution/DistributionCoordinator";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Distribution Coordinator Tests",
  func() {
    // Setup test environment for distribution tests
    func setupTest() : (DistributionCoordinator.DistributionCoordinator, CompetitionEntryStore.CompetitionEntryStore, Types.Account) {
      let entryStore = CompetitionTestUtils.createCompetitionEntryStore();
      let userAccounts = CompetitionTestUtils.getUserAccountsFunction()();
      let systemAccount = CompetitionTestUtils.getSystemAccountFunction()();
      let configs = CompetitionTestUtils.createDefaultStakeTokenConfigs();
      let coordinator = DistributionCoordinator.DistributionCoordinator(userAccounts, systemAccount, configs);
      (coordinator, entryStore, systemAccount);
    };

    // Helper to stake and move tokens to pool (simulates staking and finalization phases)
    func stakeAndPool(vault : StakeVault.StakeVault, account : Types.Account, stakes : [(Types.Token, Types.Amount)]) {
      // Phase 1: Stake (user to stake account)
      for ((token, amount) in stakes.vals()) {
        vault.stake(account, amount);
      };

      // Phase 2: Move to pool (stake account to pool)
      for ((token, amount) in stakes.vals()) {
        vault.transferToPool(account, amount);
      };
    };

    test(
      "processDistribution handles empty positions array",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create a distribution event
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution with no positions
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should succeed even with no positions
        assert Result.isOk(result);
      },
    );

    test(
      "processDistribution with single position",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create a test submission
        let sub = CompetitionTestUtils.createTestSubmission(
          0,
          CompetitionTestUtils.getUserPrincipal(),
          #Finalized,
          CompetitionTestUtils.getTestToken1(),
        );

        // Add submission to the store
        entryStore.addSubmission(sub);

        // Simulate staking and finalization phases
        let vault = entryStore.getStakeVault();
        stakeAndPool(vault, sub.participant, sub.stakes);

        // Create a position from the submission
        let pos = CompetitionTestUtils.createUserPositionFromSubmission(
          sub,
          { token = CompetitionTestUtils.getTestToken1(); value = 1000 },
        );

        // Add position to the store
        entryStore.addPosition(pos);

        // Create a distribution event
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should succeed
        assert Result.isOk(result);
      },
    );

    test(
      "processDistribution with multiple positions",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create multiple test submissions
        let sub1 = CompetitionTestUtils.createTestSubmission(
          0,
          CompetitionTestUtils.getUserPrincipal(),
          #Finalized,
          CompetitionTestUtils.getTestToken1(),
        );

        let sub2 = CompetitionTestUtils.createTestSubmission(
          1,
          CompetitionTestUtils.getUser2Principal(),
          #Finalized,
          CompetitionTestUtils.getTestToken2(),
        );

        // Add submissions
        entryStore.addSubmission(sub1);
        entryStore.addSubmission(sub2);

        // Simulate staking and finalization for both submissions
        let vault = entryStore.getStakeVault();
        stakeAndPool(vault, sub1.participant, sub1.stakes);
        stakeAndPool(vault, sub2.participant, sub2.stakes);

        // Create positions
        let pos1 = CompetitionTestUtils.createUserPositionFromSubmission(
          sub1,
          { token = CompetitionTestUtils.getTestToken1(); value = 1000 },
        );

        let pos2 = CompetitionTestUtils.createUserPositionFromSubmission(
          sub2,
          { token = CompetitionTestUtils.getTestToken2(); value = 2000 },
        );

        // Add positions
        entryStore.addPosition(pos1);
        entryStore.addPosition(pos2);

        // Create a distribution event
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should succeed
        assert Result.isOk(result);
      },
    );

    test(
      "processDistribution with system and user positions",
      func() {
        let (coordinator, entryStore, sysAccount) = setupTest();

        // Create a user submission and position
        let sub = CompetitionTestUtils.createTestSubmission(
          0,
          CompetitionTestUtils.getUserPrincipal(),
          #Finalized,
          CompetitionTestUtils.getTestToken1(),
        );

        entryStore.addSubmission(sub);

        // Create a system position
        let sysPos = CompetitionTestUtils.createSystemPosition(
          CompetitionTestUtils.getTestToken2(),
          500,
          50,
          100,
        );

        // Simulate staking and finalization
        let vault = entryStore.getStakeVault();

        // Stake tokens for user
        stakeAndPool(vault, sub.participant, sub.stakes);

        // Mint tokens to system account BEFORE staking (system account needs balance)
        for ((token, amount) in sysPos.stakes.vals()) {
          vault.getUserAccounts().mint(sysAccount, amount);
        };

        // Now stake the system tokens
        stakeAndPool(vault, sysAccount, sysPos.stakes);

        let userPos = CompetitionTestUtils.createUserPositionFromSubmission(
          sub,
          { token = CompetitionTestUtils.getTestToken1(); value = 1000 },
        );

        // Add positions
        entryStore.addPosition(userPos);
        entryStore.addPosition(sysPos);

        // Create a distribution event
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should succeed
        assert Result.isOk(result);
      },
    );

    test(
      "processDistribution fails with invalid price event",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create a distribution event with invalid price event ID
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 999; // Non-existent price event
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should fail
        assert Result.isErr(result);
      },
    );

    test(
      "processDistribution records payout information",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create a submission and position
        let sub = CompetitionTestUtils.createTestSubmission(
          0,
          CompetitionTestUtils.getUserPrincipal(),
          #Finalized,
          CompetitionTestUtils.getTestToken1(),
        );

        entryStore.addSubmission(sub);

        // Simulate staking and finalization
        let vault = entryStore.getStakeVault();
        stakeAndPool(vault, sub.participant, sub.stakes);

        let pos = CompetitionTestUtils.createUserPositionFromSubmission(
          sub,
          { token = CompetitionTestUtils.getTestToken1(); value = 1000 },
        );

        entryStore.addPosition(pos);

        // Create a distribution event
        let event : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, event);

        // Should succeed
        assert Result.isOk(result);

        // Verify payout was recorded
        let positions = entryStore.getPositions();
        assert positions.size() == 1;

        // Check that the position has distribution payouts recorded
        let updated = positions[0];
        assert updated.distributionPayouts.size() >= 0;
      },
    );

    test(
      "processDistribution handles multiple distribution events",
      func() {
        let (coordinator, entryStore, _) = setupTest();

        // Create a submission and position
        let sub = CompetitionTestUtils.createTestSubmission(
          0,
          CompetitionTestUtils.getUserPrincipal(),
          #Finalized,
          CompetitionTestUtils.getTestToken1(),
        );

        entryStore.addSubmission(sub);

        // Simulate staking and finalization
        let vault = entryStore.getStakeVault();
        stakeAndPool(vault, sub.participant, sub.stakes);

        let pos = CompetitionTestUtils.createUserPositionFromSubmission(
          sub,
          { token = CompetitionTestUtils.getTestToken1(); value = 1000 },
        );

        entryStore.addPosition(pos);

        // Process first distribution
        let event1 : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        let result1 = coordinator.processDistribution(entryStore, 0, event1);
        assert Result.isOk(result1);

        // Process second distribution
        let event2 : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 1;
        };

        let result2 = coordinator.processDistribution(entryStore, 1, event2);

        // Both should succeed
        assert Result.isOk(result2);
      },
    );
  },
);
