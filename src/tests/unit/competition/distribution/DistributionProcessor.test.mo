import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import RewardTypes "../../../../multi_backend/types/RewardTypes";
import EventTypes "../../../../multi_backend/types/EventTypes";
import DistributionProcessor "../../../../multi_backend/competition/distribution/DistributionProcessor";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import CompetitionTestUtils "../CompetitionTestUtils";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../../../../multi_backend/types/AccountTypes";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";

suite(
  "DistributionProcessor Tests",
  func() {
    // Helper to create test positions with empty payout history
    func createPosition(
      token : Types.Token,
      quantity : Nat,
      govStake : Nat,
      multiStake : Nat,
      isSystem : Bool,
      submissionId : ?Nat,
    ) : RewardTypes.Position {
      {
        quantity = { token = token; value = quantity };
        govStake = {
          token = CompetitionTestUtils.getGovToken();
          value = govStake;
        };
        multiStake = {
          token = CompetitionTestUtils.getMultiToken();
          value = multiStake;
        };
        submissionId = submissionId;
        isSystem = isSystem;
        distributionPayouts = []; // Empty payout history
      };
    };

    // Create a minimal competition entry store for testing
    func createMockEntryStore(
      positions : [RewardTypes.Position],
      submissions : [SubmissionTypes.Submission],
      stakeVault : StakeVault.StakeVault,
      userAccounts : VirtualAccounts.VirtualAccounts,
    ) : CompetitionEntryStore.CompetitionEntryStore {
      // Create a mock competition with positions
      let competition : CompetitionEntryTypes.Competition = {
        id = 1;
        startTime = 0;
        completionTime = null;
        status = #Distribution;
        config = {
          govToken = CompetitionTestUtils.getGovToken();
          multiToken = CompetitionTestUtils.getMultiToken();
          approvedTokens = [
            CompetitionTestUtils.getTestToken1(),
            CompetitionTestUtils.getTestToken2(),
            CompetitionTestUtils.getTestToken3(),
          ];
          theta = { value = 50_000_000 }; // 5%
          govRate = { value = 100_000_000 }; // 10%
          multiRate = { value = 200_000_000 }; // 20%
          systemStakeGov = { value = 1_000_000_000 }; // 100%
          systemStakeMulti = { value = 1_000_000_000 }; // 100%
          competitionCycleDuration = 86400_000_000_000; // 1 day
          preAnnouncementDuration = 3600_000_000_000; // 1 hour
          rewardDistributionDuration = 86400_000_000_000; // 1 day
          numberOfDistributionEvents = 10;
        };
        competitionPrices = 1;
        submissions = submissions;
        submissionCounter = submissions.size();
        stakeAccounts = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
        totalGovStake = 0; // Will be calculated from positions
        totalMultiStake = 0; // Will be calculated from positions
        adjustedGovRate = null;
        adjustedMultiRate = null;
        volumeLimit = 1_000_000;
        systemStake = null;
        lastDistributionIndex = null;
        nextDistributionTime = null;
        distributionHistory = [];
        positions = positions;
      };

      // Create a simple persist function
      let persistChanges = func(comp : CompetitionEntryTypes.Competition) {};

      CompetitionEntryStore.CompetitionEntryStore(
        competition,
        persistChanges,
        userAccounts,
        stakeVault,
      );
    };

    // Helper to setup test environment
    func setupTest() : (
      DistributionProcessor.DistributionProcessor,
      VirtualAccounts.VirtualAccounts,
      StakeVault.StakeVault,
      Types.Account, // system account
      Types.Account, // user1
      Types.Account, // user2
    ) {
      // Create user accounts
      let userAccounts = CompetitionTestUtils.createUserAccounts();

      // Create stake accounts and vault
      let stakeAccountsMap = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();
      let stakeVault = StakeVault.StakeVault(
        userAccounts,
        CompetitionTestUtils.getMultiToken(),
        CompetitionTestUtils.getGovToken(),
        stakeAccountsMap,
      );

      // Create processor
      let processor = DistributionProcessor.DistributionProcessor(
        CompetitionTestUtils.getGovToken(),
        CompetitionTestUtils.getMultiToken(),
      );

      // Define accounts
      let systemAccount = Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai");
      let user1 = CompetitionTestUtils.getUserPrincipal();
      let user2 = CompetitionTestUtils.getUser2Principal();

      (processor, userAccounts, stakeVault, systemAccount, user1, user2);
    };

    test(
      "processDistribution - distributes rewards correctly with equal performance",
      func() {
        let (processor, userAccounts, stakeVault, systemAccount, user1, user2) = setupTest();

        // Create positions with equal values
        let positions = [
          createPosition(CompetitionTestUtils.getTestToken1(), 1000, 1000, 2000, false, ?1), // user1
          createPosition(CompetitionTestUtils.getTestToken2(), 500, 1000, 2000, false, ?2), // user2
          createPosition(CompetitionTestUtils.getTestToken3(), 2000, 1000, 2000, true, null), // system
        ];

        // Create submissions for the positions
        let submissions : [SubmissionTypes.Submission] = [
          {
            id = 1;
            participant = user1;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 1000;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 2000;
            };
            token = CompetitionTestUtils.getTestToken1();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            executionPrice = null;
            positionId = ?0;
          },
          {
            id = 2;
            participant = user2;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 1000;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 2000;
            };
            token = CompetitionTestUtils.getTestToken2();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken2();
              value = 500;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 500;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 500;
            };
            executionPrice = null;
            positionId = ?1;
          },
        ];

        // Create entry store
        let entryStore = createMockEntryStore(positions, submissions, stakeVault, userAccounts);

        // Pre-fund the POOL account with rewards for one distribution
        // Total stakes: 3000 GOV, 6000 MULTI
        // Per distribution (10 distributions): 300 GOV, 600 MULTI
        let poolAccount = stakeVault.getPoolAccount();
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getGovToken();
            value = 300;
          },
        );
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getMultiToken();
            value = 600;
          },
        );

        // Record initial balances
        let user1GovBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value;
        let user2GovBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value;
        let systemGovBefore = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken()).value;

        let user1MultiBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value;
        let user2MultiBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value;
        let systemMultiBefore = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value;

        // Create price event - prices that make all positions equal value (1000 Multi)
        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() }; // 1.0
            },
            {
              baseToken = CompetitionTestUtils.getTestToken2();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = {
                value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
              }; // 2.0
            },
            {
              baseToken = CompetitionTestUtils.getTestToken3();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = { value = CompetitionTestUtils.getFIFTY_PERCENT() }; // 0.5
            },
          ];
        };

        // Account mapping function
        let getPositionAccount = func(position : RewardTypes.Position) : ?Types.Account {
          switch (position.submissionId) {
            case (?1) { ?user1 };
            case (?2) { ?user2 };
            case (_) { null };
          };
        };

        // Process distribution
        processor.processDistribution(
          positions,
          priceEvent,
          0, // distributionNumber
          10, // totalDistributions
          stakeVault,
          systemAccount,
          getPositionAccount,
          entryStore,
        );

        // Check final balances
        // Each position should get 1/3 of rewards (equal performance)
        // 300 GOV / 3 = 100 GOV each
        // 600 MULTI / 3 = 200 MULTI each
        assert userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value == user1GovBefore + 100;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value == user2GovBefore + 100;
        assert userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken()).value == systemGovBefore + 100;

        assert userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value == user1MultiBefore + 200;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value == user2MultiBefore + 200;
        assert userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value == systemMultiBefore + 200;

        // Verify pool is empty
        assert stakeVault.getStakeAccounts().getBalance(poolAccount, CompetitionTestUtils.getGovToken()).value == 0;
        assert stakeVault.getStakeAccounts().getBalance(poolAccount, CompetitionTestUtils.getMultiToken()).value == 0;
      },
    );

    test(
      "processDistribution - distributes rewards proportionally to performance",
      func() {
        let (processor, userAccounts, stakeVault, systemAccount, user1, user2) = setupTest();

        // Create positions with different values
        let positions = [
          createPosition(CompetitionTestUtils.getTestToken1(), 3000, 600, 1200, false, ?1), // user1 - 75% value
          createPosition(CompetitionTestUtils.getTestToken2(), 1000, 400, 800, false, ?2), // user2 - 25% value
        ];

        // Create submissions
        let submissions : [SubmissionTypes.Submission] = [
          {
            id = 1;
            participant = user1;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 600;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 1200;
            };
            token = CompetitionTestUtils.getTestToken1();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken1();
              value = 3000;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 3000;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 3000;
            };
            executionPrice = null;
            positionId = ?0;
          },
          {
            id = 2;
            participant = user2;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 400;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 800;
            };
            token = CompetitionTestUtils.getTestToken2();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            executionPrice = null;
            positionId = ?1;
          },
        ];

        let entryStore = createMockEntryStore(positions, submissions, stakeVault, userAccounts);

        // Pre-fund the POOL account for 1 distribution
        let poolAccount = stakeVault.getPoolAccount();
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getGovToken();
            value = 1000;
          },
        );
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getMultiToken();
            value = 2000;
          },
        );

        // Record initial balances
        let user1GovBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value;
        let user2GovBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value;
        let user1MultiBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value;
        let user2MultiBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value;

        // Price event - same price for simplicity
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

        let getPositionAccount = func(position : RewardTypes.Position) : ?Types.Account {
          switch (position.submissionId) {
            case (?1) { ?user1 };
            case (?2) { ?user2 };
            case (_) { null };
          };
        };

        processor.processDistribution(
          positions,
          priceEvent,
          0, // distributionNumber (only 1 distribution)
          1, // totalDistributions
          stakeVault,
          systemAccount,
          getPositionAccount,
          entryStore,
        );

        // User1 should get 75% of rewards, User2 gets 25%
        assert userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value == user1GovBefore + 750;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value == user2GovBefore + 250;

        assert userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value == user1MultiBefore + 1500;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value == user2MultiBefore + 500;
      },
    );

    test(
      "processDistribution - handles last distribution with remainder",
      func() {
        let (processor, userAccounts, stakeVault, systemAccount, user1, user2) = setupTest();

        // Create positions with stakes that don't divide evenly
        let positions = [
          createPosition(CompetitionTestUtils.getTestToken1(), 1000, 333, 667, false, ?1), // user1
          createPosition(CompetitionTestUtils.getTestToken2(), 1000, 334, 666, false, ?2), // user2
        ];

        let submissions : [SubmissionTypes.Submission] = [
          {
            id = 1;
            participant = user1;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 333;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 667;
            };
            token = CompetitionTestUtils.getTestToken1();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken1();
              value = 1000;
            };
            executionPrice = null;
            positionId = ?0;
          },
          {
            id = 2;
            participant = user2;
            govStake = {
              token = CompetitionTestUtils.getGovToken();
              value = 334;
            };
            multiStake = {
              token = CompetitionTestUtils.getMultiToken();
              value = 666;
            };
            token = CompetitionTestUtils.getTestToken2();
            proposedQuantity = {
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            timestamp = 0;
            status = #Settled;
            rejectionReason = null;
            adjustedQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            soldQuantity = ?{
              token = CompetitionTestUtils.getTestToken2();
              value = 1000;
            };
            executionPrice = null;
            positionId = ?1;
          },
        ];

        let entryStore = createMockEntryStore(positions, submissions, stakeVault, userAccounts);

        // Total stakes: 667 GOV, 1333 MULTI
        // With 3 distributions:
        // - User1: 333/3 = 111 per dist, 667/3 = 222 per dist + 1 remainder
        // - User2: 334/3 = 111 per dist + 1 remainder, 666/3 = 222 per dist
        // Last distribution pool should be 111+111+1 = 223 GOV, 222+222+1 = 445 MULTI
        let poolAccount = stakeVault.getPoolAccount();
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getGovToken();
            value = 223;
          },
        );
        stakeVault.getStakeAccounts().mint(
          poolAccount,
          {
            token = CompetitionTestUtils.getMultiToken();
            value = 445;
          },
        );

        // Record initial balances
        let user1GovBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value;
        let user2GovBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value;
        let user1MultiBefore = userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value;
        let user2MultiBefore = userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value;

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

        let getPositionAccount = func(position : RewardTypes.Position) : ?Types.Account {
          switch (position.submissionId) {
            case (?1) { ?user1 };
            case (?2) { ?user2 };
            case (_) { null };
          };
        };

        // Process the LAST distribution (index 2 of 3)
        processor.processDistribution(
          positions,
          priceEvent,
          2, // Last distribution (0-based)
          3, // Total distributions
          stakeVault,
          systemAccount,
          getPositionAccount,
          entryStore,
        );

        // Check balances (equal performance, so split 50/50)
        // Remainders are distributed round-robin starting from position 0:
        // GOV pool: 223 total, 111 each + 1 remainder -> user1 gets 112, user2 gets 111
        // MULTI pool: 445 total, 222 each + 1 remainder -> user1 gets 223, user2 gets 222
        assert userAccounts.getBalance(user1, CompetitionTestUtils.getGovToken()).value == user1GovBefore + 112;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getGovToken()).value == user2GovBefore + 111;

        assert userAccounts.getBalance(user1, CompetitionTestUtils.getMultiToken()).value == user1MultiBefore + 223;
        assert userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value == user2MultiBefore + 222;
      },
    );
  },
);
