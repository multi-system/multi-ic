import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Iter "mo:base/Iter";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import RewardTypes "../../../../multi_backend/types/RewardTypes";
import EventTypes "../../../../multi_backend/types/EventTypes";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import Error "../../../../multi_backend/error/Error";
import DistributionCoordinator "../../../../multi_backend/competition/distribution/DistributionCoordinator";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import CompetitionTestUtils "../CompetitionTestUtils";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../../../../multi_backend/types/AccountTypes";

suite(
  "DistributionCoordinator Tests",
  func() {
    // Helper to create a mock entry store with configurable data
    func createMockEntryStore(
      positions : [RewardTypes.Position],
      submissions : [SubmissionTypes.Submission],
      distributionPrices : ?EventTypes.PriceEvent,
      userAccounts : VirtualAccounts.VirtualAccounts,
    ) : CompetitionEntryStore.CompetitionEntryStore {
      // Create a mock competition
      let competition : CompetitionEntryTypes.Competition = {
        id = 1;
        startTime = 0;
        completionTime = null;
        status = #Distribution;
        config = {
          multiToken = CompetitionTestUtils.getMultiToken();
          approvedTokens = [
            CompetitionTestUtils.getTestToken1(),
            CompetitionTestUtils.getTestToken2(),
          ];
          theta = { value = 50_000_000 };
          stakeTokenConfigs = CompetitionTestUtils.createDefaultStakeTokenConfigs();
          competitionCycleDuration = 86400_000_000_000;
          preAnnouncementDuration = 3600_000_000_000;
          rewardDistributionDuration = 86400_000_000_000;
          numberOfDistributionEvents = 10;
        };
        competitionPrices = 1;
        submissions = submissions;
        submissionCounter = submissions.size();
        stakeAccounts = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
        totalStakes = [
          (CompetitionTestUtils.getGovToken(), 1000),
          (CompetitionTestUtils.getMultiToken(), 2000),
        ];
        adjustedRates = null;
        volumeLimit = 1_000_000;
        systemStake = null;
        lastDistributionIndex = null;
        nextDistributionTime = null;
        distributionHistory = [];
        positions = positions;
      };

      let stakeVault = StakeVault.StakeVault(
        userAccounts,
        competition.config.stakeTokenConfigs,
        competition.stakeAccounts,
      );

      let entryStore = CompetitionEntryStore.CompetitionEntryStore(
        competition,
        func(updated : CompetitionEntryTypes.Competition) {},
        userAccounts,
        stakeVault,
      );

      // Mock the price event retriever
      entryStore.setPriceEventRetriever(
        func(id : Nat) : ?EventTypes.PriceEvent {
          distributionPrices;
        }
      );

      // Pre-fund the pool for testing
      let poolAccount = stakeVault.getPoolAccount();
      stakeVault.getStakeAccounts().mint(
        poolAccount,
        { token = CompetitionTestUtils.getGovToken(); value = 100 },
      );
      stakeVault.getStakeAccounts().mint(
        poolAccount,
        { token = CompetitionTestUtils.getMultiToken(); value = 200 },
      );

      entryStore;
    };

    // Helper to create test positions
    func createTestPosition(
      token : Types.Token,
      submissionId : ?Nat,
      isSystem : Bool,
    ) : RewardTypes.Position {
      {
        quantity = { token = token; value = 1000 };
        stakes = [
          (CompetitionTestUtils.getGovToken(), { token = CompetitionTestUtils.getGovToken(); value = 100 }),
          (CompetitionTestUtils.getMultiToken(), { token = CompetitionTestUtils.getMultiToken(); value = 200 }),
        ];
        submissionId = submissionId;
        isSystem = isSystem;
        distributionPayouts = [];
      };
    };

    // Helper to create test submission
    func createTestSubmission(
      id : Nat,
      participant : Types.Account,
      token : Types.Token,
    ) : SubmissionTypes.Submission {
      {
        id = id;
        participant = participant;
        stakes = [
          (CompetitionTestUtils.getGovToken(), { token = CompetitionTestUtils.getGovToken(); value = 100 }),
          (CompetitionTestUtils.getMultiToken(), { token = CompetitionTestUtils.getMultiToken(); value = 200 }),
        ];
        token = token;
        proposedQuantity = { token = token; value = 1000 };
        timestamp = 0;
        status = #Settled;
        rejectionReason = null;
        adjustedQuantity = ?{ token = token; value = 1000 };
        soldQuantity = ?{ token = token; value = 1000 };
        executionPrice = null;
        positionId = ?0;
      };
    };

    test(
      "processDistribution - handles positions correctly",
      func() {
        let userAccounts = CompetitionTestUtils.createUserAccounts();
        let systemAccount = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");
        let user1 = CompetitionTestUtils.getUserPrincipal();
        let user2 = CompetitionTestUtils.getUser2Principal();

        let coordinator = DistributionCoordinator.DistributionCoordinator(
          userAccounts,
          systemAccount,
          CompetitionTestUtils.createDefaultStakeTokenConfigs(),
        );

        // Create positions with different types
        let positions = [
          createTestPosition(CompetitionTestUtils.getTestToken1(), ?1, false), // User position
          createTestPosition(CompetitionTestUtils.getTestToken2(), ?2, false), // User position
          createTestPosition(CompetitionTestUtils.getTestToken1(), null, true), // System position
        ];

        let submissions = [
          createTestSubmission(1, user1, CompetitionTestUtils.getTestToken1()),
          createTestSubmission(2, user2, CompetitionTestUtils.getTestToken2()),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
            {
              baseToken = CompetitionTestUtils.getTestToken2();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
          ];
        };

        let entryStore = createMockEntryStore(positions, submissions, ?priceEvent, userAccounts);

        let distributionEvent : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Should process successfully
        let result = coordinator.processDistribution(entryStore, 0, distributionEvent);
        assert Result.isOk(result);

        // Verify users received rewards (basic check - detailed testing in processor)
        let user1Balance = userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value;
        let user2Balance = userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value;
        let systemBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken()).value;

        // All should have received some rewards
        assert user1Balance > 0;
        assert user2Balance > 0;
        assert systemBalance > 0;
      },
    );

    // Note: We can't test trap behavior in mo:test framework directly
    // These tests would need to be integration tests or use a different approach

    test(
      "processDistribution - correctly maps positions to accounts",
      func() {
        let userAccounts = CompetitionTestUtils.createUserAccounts();
        let systemAccount = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");
        let user1 = CompetitionTestUtils.getUserPrincipal();
        let user2 = CompetitionTestUtils.getUser2Principal();

        let coordinator = DistributionCoordinator.DistributionCoordinator(
          userAccounts,
          systemAccount,
          CompetitionTestUtils.createDefaultStakeTokenConfigs(),
        );

        // Create positions with specific submission IDs
        let positions = [
          createTestPosition(CompetitionTestUtils.getTestToken1(), ?1, false), // Maps to user1
          createTestPosition(CompetitionTestUtils.getTestToken2(), ?2, false), // Maps to user2
          createTestPosition(CompetitionTestUtils.getTestToken2(), null, true), // System position
        ];

        let submissions = [
          createTestSubmission(1, user1, CompetitionTestUtils.getTestToken1()),
          createTestSubmission(2, user2, CompetitionTestUtils.getTestToken2()),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
            {
              baseToken = CompetitionTestUtils.getTestToken2();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
          ];
        };

        let entryStore = createMockEntryStore(positions, submissions, ?priceEvent, userAccounts);

        // Pre-fund pool with more tokens for 3 positions
        let poolAccount = entryStore.getStakeVault().getPoolAccount();
        entryStore.getStakeVault().getStakeAccounts().mint(
          poolAccount,
          { token = CompetitionTestUtils.getGovToken(); value = 200 } // 300 total
        );
        entryStore.getStakeVault().getStakeAccounts().mint(
          poolAccount,
          { token = CompetitionTestUtils.getMultiToken(); value = 400 } // 600 total
        );

        let distributionEvent : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        // Process distribution
        let result = coordinator.processDistribution(entryStore, 0, distributionEvent);
        assert Result.isOk(result);

        // Verify correct account mapping
        let user1Gov = userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value;
        let user2Gov = userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value;
        let systemGov = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken()).value;

        // User1 and User2 should have received rewards
        assert user1Gov > 0;
        assert user2Gov > 0;

        // System should have received rewards for system position
        assert systemGov > 0;
      },
    );

    test(
      "processDistribution - handles distribution events correctly",
      func() {
        let userAccounts = CompetitionTestUtils.createUserAccounts();
        let systemAccount = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");

        let coordinator = DistributionCoordinator.DistributionCoordinator(
          userAccounts,
          systemAccount,
          CompetitionTestUtils.createDefaultStakeTokenConfigs(),
        );

        let positions = [
          createTestPosition(CompetitionTestUtils.getTestToken1(), ?1, false),
        ];

        let submissions = [
          createTestSubmission(1, CompetitionTestUtils.getUserPrincipal(), CompetitionTestUtils.getTestToken1()),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
          ];
        };

        let entryStore = createMockEntryStore(positions, submissions, ?priceEvent, userAccounts);

        // Test different distribution numbers
        for (i in Iter.range(0, 2)) {
          let distributionEvent : CompetitionEntryTypes.DistributionEvent = {
            distributionPrices = 1;
            distributionNumber = i;
          };

          let result = coordinator.processDistribution(entryStore, i, distributionEvent);
          assert Result.isOk(result);
        };
      },
    );

    test(
      "processDistribution - records payout history correctly",
      func() {
        let userAccounts = CompetitionTestUtils.createUserAccounts();
        let systemAccount = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");
        let user1 = CompetitionTestUtils.getUserPrincipal();

        let coordinator = DistributionCoordinator.DistributionCoordinator(
          userAccounts,
          systemAccount,
          CompetitionTestUtils.createDefaultStakeTokenConfigs(),
        );

        // Create multiple positions to test payout recording
        let positions = [
          createTestPosition(CompetitionTestUtils.getTestToken1(), ?1, false), // User position
          createTestPosition(CompetitionTestUtils.getTestToken2(), null, true), // System position
        ];

        let submissions = [
          createTestSubmission(1, user1, CompetitionTestUtils.getTestToken1()),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
            {
              baseToken = CompetitionTestUtils.getTestToken2();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
            },
          ];
        };

        let entryStore = createMockEntryStore(positions, submissions, ?priceEvent, userAccounts);

        // The pool is pre-funded with 100 GOV and 200 MULTI in createMockEntryStore
        // But we need 20 GOV and 40 MULTI per distribution (total stakes divided by 10)
        // So we need to add more funds for our two test distributions
        let poolAccount = entryStore.getStakeVault().getPoolAccount();

        // First distribution needs 20 GOV, 40 MULTI
        // Pool has 100 GOV, 200 MULTI, so we have enough

        // Process first distribution
        let distributionEvent0 : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 0;
        };

        let result0 = coordinator.processDistribution(entryStore, 0, distributionEvent0);
        assert Result.isOk(result0);

        // Check payout history after first distribution
        let positionsAfter0 = entryStore.getPositions();
        assert positionsAfter0.size() == 2;

        // Check position 0 (user position) payout history
        let pos0Payouts = positionsAfter0[0].distributionPayouts;
        assert pos0Payouts.size() == 1;
        assert pos0Payouts[0].distributionNumber == 0;

        // Access payouts through the array structure
        var pos0GovPayout = 0;
        var pos0MultiPayout = 0;
        for ((token, amount) in pos0Payouts[0].payouts.vals()) {
          if (Principal.equal(token, CompetitionTestUtils.getGovToken())) {
            pos0GovPayout := amount;
          };
          if (Principal.equal(token, CompetitionTestUtils.getMultiToken())) {
            pos0MultiPayout := amount;
          };
        };
        assert pos0GovPayout > 0;
        assert pos0MultiPayout > 0;

        // Check position 1 (system position) payout history
        let pos1Payouts = positionsAfter0[1].distributionPayouts;
        assert pos1Payouts.size() == 1;
        assert pos1Payouts[0].distributionNumber == 0;

        var pos1GovPayout = 0;
        var pos1MultiPayout = 0;
        for ((token, amount) in pos1Payouts[0].payouts.vals()) {
          if (Principal.equal(token, CompetitionTestUtils.getGovToken())) {
            pos1GovPayout := amount;
          };
          if (Principal.equal(token, CompetitionTestUtils.getMultiToken())) {
            pos1MultiPayout := amount;
          };
        };
        assert pos1GovPayout > 0;
        assert pos1MultiPayout > 0;

        // Fund pool again for second distribution (20 GOV, 40 MULTI needed)
        entryStore.getStakeVault().getStakeAccounts().mint(
          poolAccount,
          { token = CompetitionTestUtils.getGovToken(); value = 20 },
        );
        entryStore.getStakeVault().getStakeAccounts().mint(
          poolAccount,
          { token = CompetitionTestUtils.getMultiToken(); value = 40 },
        );

        // Process second distribution
        let distributionEvent1 : CompetitionEntryTypes.DistributionEvent = {
          distributionPrices = 1;
          distributionNumber = 1;
        };

        let result1 = coordinator.processDistribution(entryStore, 1, distributionEvent1);
        assert Result.isOk(result1);

        // Check payout history after second distribution
        let positionsAfter1 = entryStore.getPositions();

        // Position 0 should now have 2 payout records
        let pos0PayoutsAfter = positionsAfter1[0].distributionPayouts;
        assert pos0PayoutsAfter.size() == 2;
        assert pos0PayoutsAfter[1].distributionNumber == 1;

        var pos0GovPayout2 = 0;
        var pos0MultiPayout2 = 0;
        for ((token, amount) in pos0PayoutsAfter[1].payouts.vals()) {
          if (Principal.equal(token, CompetitionTestUtils.getGovToken())) {
            pos0GovPayout2 := amount;
          };
          if (Principal.equal(token, CompetitionTestUtils.getMultiToken())) {
            pos0MultiPayout2 := amount;
          };
        };
        assert pos0GovPayout2 > 0;
        assert pos0MultiPayout2 > 0;

        // Position 1 should also have 2 payout records
        let pos1PayoutsAfter = positionsAfter1[1].distributionPayouts;
        assert pos1PayoutsAfter.size() == 2;
        assert pos1PayoutsAfter[1].distributionNumber == 1;

        var pos1GovPayout2 = 0;
        var pos1MultiPayout2 = 0;
        for ((token, amount) in pos1PayoutsAfter[1].payouts.vals()) {
          if (Principal.equal(token, CompetitionTestUtils.getGovToken())) {
            pos1GovPayout2 := amount;
          };
          if (Principal.equal(token, CompetitionTestUtils.getMultiToken())) {
            pos1MultiPayout2 := amount;
          };
        };
        assert pos1GovPayout2 > 0;
        assert pos1MultiPayout2 > 0;

        // Verify total rewards sum matches pool amount
        let totalGovRewards = pos0GovPayout + pos1GovPayout;
        let totalMultiRewards = pos0MultiPayout + pos1MultiPayout;

        // Each distribution should distribute 1/10 of total stakes
        // Total stakes: 200 GOV, 400 MULTI
        // Per distribution: 20 GOV, 40 MULTI
        assert totalGovRewards == 20;
        assert totalMultiRewards == 40;
      },
    );
  },
);
