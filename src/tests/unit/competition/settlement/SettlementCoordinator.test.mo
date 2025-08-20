import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import { suite; test; expect } "mo:test";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import SystemStakeTypes "../../../../multi_backend/types/SystemStakeTypes";
import SettlementTypes "../../../../multi_backend/types/SettlementTypes";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import BackingOperations "../../../../multi_backend/backing/BackingOperations";
import BackingStore "../../../../multi_backend/backing/BackingStore";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import SettlementCoordinator "../../../../multi_backend/competition/settlement/SettlementCoordinator";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Settlement Coordinator",
  func() {
    // Setup test environment
    let setupTest = func() : (
      SettlementCoordinator.SettlementCoordinator,
      VirtualAccounts.VirtualAccounts,
      VirtualAccounts.VirtualAccounts,
      Principal,
      BackingStore.BackingStore,
    ) {
      // Create virtual accounts
      let userAccounts = CompetitionTestUtils.createUserAccounts();
      let stakeAccounts = VirtualAccounts.VirtualAccounts(
        StableHashMap.init<Types.Account, StableHashMap.StableHashMap<Types.Token, Nat>>()
      );

      // Create backing store
      let backingState : BackingTypes.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 1000; // Supply unit of 1000
          totalSupply = 0;
          backingPairs = [];
          multiToken = CompetitionTestUtils.getMultiToken();
        };
      };

      let backingStore = BackingStore.BackingStore(backingState);
      backingStore.initialize(1000, CompetitionTestUtils.getMultiToken());

      // Add backing tokens
      backingStore.updateBackingTokens([
        {
          token = CompetitionTestUtils.getTestToken1();
          backingUnit = 10;
        },
        {
          token = CompetitionTestUtils.getTestToken2();
          backingUnit = 20;
        },
      ]);

      // Create system account with valid Principal
      let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

      // Create backing operations
      let backingOps = BackingOperations.BackingOperations(
        backingStore,
        userAccounts,
        systemAccount,
      );

      // Create stake token configs
      let stakeTokenConfigs : [(Types.Token, Types.Ratio)] = [
        (CompetitionTestUtils.getGovToken(), { value = CompetitionTestUtils.getFIVE_PERCENT() }),
        (CompetitionTestUtils.getMultiToken(), { value = CompetitionTestUtils.getONE_PERCENT() }),
      ];

      // Create settlement coordinator with stake token configs
      let settlementCoordinator = SettlementCoordinator.SettlementCoordinator(
        userAccounts,
        stakeAccounts,
        backingOps,
        backingStore,
        stakeTokenConfigs,
        systemAccount,
      );

      (settlementCoordinator, userAccounts, stakeAccounts, systemAccount, backingStore);
    };

    // Helper to create finalized submissions
    let createFinalizedSubmissions = func() : [SubmissionTypes.Submission] {
      let testUser = CompetitionTestUtils.getUserPrincipal();
      let token1 = CompetitionTestUtils.getTestToken1();
      let token2 = CompetitionTestUtils.getTestToken2();
      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();

      // Create adjusted quantities
      let quantity1 : Types.Amount = {
        token = token1;
        value = 20_000;
      };

      let quantity2 : Types.Amount = {
        token = token2;
        value = 10_000;
      };

      // Create two test submissions with flexible stakes
      let submission1 : SubmissionTypes.Submission = {
        id = 0;
        participant = testUser;
        stakes = [
          (govToken, { token = govToken; value = 1000 }),
          (multiToken, { token = multiToken; value = 200 }),
        ];
        token = token1;
        proposedQuantity = quantity1;
        timestamp = 0;
        status = #Finalized;
        rejectionReason = null;
        adjustedQuantity = ?quantity1;
        soldQuantity = null;
        executionPrice = null;
        positionId = null;
      };

      let submission2 : SubmissionTypes.Submission = {
        id = 1;
        participant = testUser;
        stakes = [
          (govToken, { token = govToken; value = 2000 }),
          (multiToken, { token = multiToken; value = 400 }),
        ];
        token = token2;
        proposedQuantity = quantity2;
        timestamp = 0;
        status = #Finalized;
        rejectionReason = null;
        adjustedQuantity = ?quantity2;
        soldQuantity = null;
        executionPrice = null;
        positionId = null;
      };

      [submission1, submission2];
    };

    // Helper to create a test system stake
    let createTestSystemStake = func() : SystemStakeTypes.SystemStake {
      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();
      let token1 = CompetitionTestUtils.getTestToken1();
      let token2 = CompetitionTestUtils.getTestToken2();

      // Create system stakes array
      let systemStakes : [(Types.Token, Types.Amount)] = [
        (govToken, { token = govToken; value = 5_000 }),
        (multiToken, { token = multiToken; value = 3_000 }),
      ];

      // Create phantom positions for test tokens
      let phantomPositions : [(Types.Token, Types.Amount)] = [
        (token1, { token = token1; value = 5_000 }),
        (token2, { token = token2; value = 3_000 }),
      ];

      {
        systemStakes;
        phantomPositions;
      };
    };

    test(
      "creates execution prices correctly",
      func() {
        let (coordinator, _, _, _, _) = setupTest();

        // Create competition prices
        let multiToken = CompetitionTestUtils.getMultiToken();
        let token1 = CompetitionTestUtils.getTestToken1();
        let token2 = CompetitionTestUtils.getTestToken2();

        let competitionPrices = [
          {
            baseToken = token1;
            quoteToken = multiToken;
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
            }; // 1.0
          },
          {
            baseToken = token2;
            quoteToken = multiToken;
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
            }; // 2.0
          },
        ];

        // Call the function under test
        let executionPrices = coordinator.createExecutionPrices(competitionPrices);

        // Verify results
        expect.nat(executionPrices.size()).equal(2);

        expect.principal(executionPrices[0].token).equal(token1);
        expect.principal(executionPrices[0].executionPrice.baseToken).equal(token1);
        expect.principal(executionPrices[0].executionPrice.quoteToken).equal(multiToken);
        expect.nat(executionPrices[0].executionPrice.value.value).equal(CompetitionTestUtils.getONE_HUNDRED_PERCENT());

        expect.principal(executionPrices[1].token).equal(token2);
        expect.principal(executionPrices[1].executionPrice.baseToken).equal(token2);
        expect.principal(executionPrices[1].executionPrice.quoteToken).equal(multiToken);
        expect.nat(executionPrices[1].executionPrice.value.value).equal(CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2);
      },
    );

    test(
      "executes settlement process",
      func() {
        let (coordinator, userAccounts, stakeAccounts, systemAccount, backingStore) = setupTest();

        // Create test data
        let submissions = createFinalizedSubmissions();
        let systemStake = createTestSystemStake();
        let testUser = CompetitionTestUtils.getUserPrincipal();

        // Add tokens to stake accounts
        for (submission in submissions.vals()) {
          // Properly unwrap the optional value
          switch (submission.adjustedQuantity) {
            case (?adjustedQuantity) {
              stakeAccounts.mint(submission.participant, adjustedQuantity);
            };
            case (null) {
              Debug.trap("Unexpected null adjustedQuantity");
            };
          };
          // Mint all stakes
          for ((_, amount) in submission.stakes.vals()) {
            stakeAccounts.mint(submission.participant, amount);
          };
        };

        // Create execution prices
        let executionPrices = coordinator.createExecutionPrices([
          {
            baseToken = CompetitionTestUtils.getTestToken1();
            quoteToken = CompetitionTestUtils.getMultiToken();
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
            }; // 1.0
          },
          {
            baseToken = CompetitionTestUtils.getTestToken2();
            quoteToken = CompetitionTestUtils.getMultiToken();
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
            }; // 2.0
          },
        ]);

        // Verify starting balances
        expect.nat(stakeAccounts.getBalance(testUser, CompetitionTestUtils.getTestToken1()).value).equal(20_000);
        expect.nat(stakeAccounts.getBalance(testUser, CompetitionTestUtils.getTestToken2()).value).equal(10_000);
        expect.nat(userAccounts.getBalance(testUser, CompetitionTestUtils.getMultiToken()).value).equal(50_000); // Initial balance

        // Execute settlement
        let settlementRecord = coordinator.executeSettlement(
          submissions,
          systemStake,
          executionPrices,
        );

        // Verify settlement record - skip exact timestamp comparison
        // expect.nat(settlementRecord.timestamp).equal(Time.now()); // This won't work reliably
        expect.nat(settlementRecord.tokenAmounts.size()).equal(2);

        // Verify token flows:

        // 1. Tokens should be transferred from stake accounts to user accounts to system account
        expect.nat(stakeAccounts.getBalance(testUser, CompetitionTestUtils.getTestToken1()).value).equal(0);
        expect.nat(stakeAccounts.getBalance(testUser, CompetitionTestUtils.getTestToken2()).value).equal(0);
        expect.nat(userAccounts.getBalance(systemAccount, CompetitionTestUtils.getTestToken1()).value).equal(20_000);
        expect.nat(userAccounts.getBalance(systemAccount, CompetitionTestUtils.getTestToken2()).value).equal(10_000);

        // 2. User should receive Multi tokens for submissions
        // For token1: 20,000 * 1.0 = 20,000 Multi value
        // For token2: 10,000 * 2.0 = 20,000 Multi value
        // Total value: 40,000 Multi
        // With alignment to 1000, should mint 40,000 Multi
        expect.nat(settlementRecord.multiMinted.value).equal(40_000);

        // 3. System stake should also be minted
        // Original value was 3,000, aligned to supply unit should be 3,000
        expect.nat(settlementRecord.systemStakeMinted.value).equal(3_000);

        // 4. Backing tokens should be updated after settlement
        let backingTokens = backingStore.getBackingTokens();
        expect.nat(backingTokens.size()).equal(2);
      },
    );

    test(
      "properly updates backing ratios after settlement with exact precision",
      func() {
        let (coordinator, userAccounts, stakeAccounts, systemAccount, backingStore) = setupTest();

        // Create test data with precise values
        let baseSubmissions = createFinalizedSubmissions();
        let systemStake = createTestSystemStake();
        let testUser = CompetitionTestUtils.getUserPrincipal();
        let token1 = CompetitionTestUtils.getTestToken1();
        let token2 = CompetitionTestUtils.getTestToken2();

        // Create modified submissions with exact quantities
        let submission1 = {
          baseSubmissions[0] with
          adjustedQuantity = ?{
            token = token1;
            value = 30_000;
          }
        };

        let submission2 = {
          baseSubmissions[1] with
          adjustedQuantity = ?{
            token = token2;
            value = 15_000;
          }
        };

        // Use the modified submissions array
        let submissions = [submission1, submission2];

        // Add tokens to stake accounts with the exact adjusted quantities
        for (submission in submissions.vals()) {
          switch (submission.adjustedQuantity) {
            case (?adjustedQuantity) {
              stakeAccounts.mint(submission.participant, adjustedQuantity);
            };
            case (null) {
              Debug.trap("Unexpected null adjustedQuantity");
            };
          };
          // Mint all stakes
          for ((_, amount) in submission.stakes.vals()) {
            stakeAccounts.mint(submission.participant, amount);
          };
        };

        // Create execution prices with exact values that will result in clean division
        let executionPrices = coordinator.createExecutionPrices([
          {
            baseToken = token1;
            quoteToken = CompetitionTestUtils.getMultiToken();
            value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() }; // 1.0
          },
          {
            baseToken = token2;
            quoteToken = CompetitionTestUtils.getMultiToken();
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
            }; // 2.0
          },
        ]);

        // Execute settlement
        let settlementRecord = coordinator.executeSettlement(
          submissions,
          systemStake,
          executionPrices,
        );

        // Calculate expected values based on the whitepaper's formulas
        // For token1: 30,000 * 1.0 = 30,000 Multi value
        // For token2: 15,000 * 2.0 = 30,000 Multi value
        // Total value: 60,000 Multi

        // Get token balances in system account after settlement
        let token1Balance = userAccounts.getBalance(systemAccount, token1).value;
        let token2Balance = userAccounts.getBalance(systemAccount, token2).value;

        // Verify expected balances match exactly
        expect.nat(token1Balance).equal(30_000);
        expect.nat(token2Balance).equal(15_000);

        // Verify total supply has been updated correctly
        // Should be multiMinted + systemStakeMinted
        let totalSupply = backingStore.getTotalSupply().value;
        expect.nat(totalSupply).equal(settlementRecord.multiMinted.value + settlementRecord.systemStakeMinted.value);

        // Get updated backing tokens
        let updatedBackingTokens = backingStore.getBackingTokens();
        expect.nat(updatedBackingTokens.size()).equal(2);

        // The supply unit is 1000, so calculate eta = totalSupply / supplyUnit
        let supplyUnit = backingStore.getSupplyUnit();
        let eta = totalSupply / supplyUnit;

        // Calculate expected backing units using the exact formula from BackingMath:
        // backingUnit = reserveAmount / eta
        let expectedBackingUnit1 = token1Balance / eta;
        let expectedBackingUnit2 = token2Balance / eta;

        // Verify backing units match exactly with no tolerance for error
        let token1Index = if (Principal.equal(updatedBackingTokens[0].token, token1)) 0 else 1;
        let token2Index = 1 - token1Index; // The other index

        expect.nat(updatedBackingTokens[token1Index].backingUnit).equal(expectedBackingUnit1);
        expect.nat(updatedBackingTokens[token2Index].backingUnit).equal(expectedBackingUnit2);

        // Verify the ratio of backing units matches the expected ratio
        // If token1Balance = 30,000 and token2Balance = 15,000
        // Then the backing units should maintain a 2:1 ratio exactly
        let backingUnitRatio = updatedBackingTokens[token1Index].backingUnit * 1_000_000 / updatedBackingTokens[token2Index].backingUnit;
        expect.nat(backingUnitRatio).equal(2_000_000); // 2.0 with 6 decimal precision
      },
    );

    test(
      "handles complex settlement scenario with multiple assets and users",
      func() {
        let (coordinator, userAccounts, stakeAccounts, systemAccount, backingStore) = setupTest();

        // Add a third token to the backing store
        let token3 = CompetitionTestUtils.getTestToken3();
        backingStore.updateBackingTokens([
          {
            token = CompetitionTestUtils.getTestToken1();
            backingUnit = 10;
          },
          {
            token = CompetitionTestUtils.getTestToken2();
            backingUnit = 20;
          },
          {
            token = token3;
            backingUnit = 30;
          },
        ]);

        // Get initial backing tokens
        let initialBackingTokens = backingStore.getBackingTokens();
        expect.nat(initialBackingTokens.size()).equal(3);

        // Add a second test user
        let testUser = CompetitionTestUtils.getUserPrincipal();
        let testUser2 = CompetitionTestUtils.getUser2Principal();
        let token1 = CompetitionTestUtils.getTestToken1();
        let token2 = CompetitionTestUtils.getTestToken2();
        let govToken = CompetitionTestUtils.getGovToken();
        let multiToken = CompetitionTestUtils.getMultiToken();

        // PHASE 1: First settlement with two users and three tokens

        // Create base submissions with flexible stakes
        let baseSubmission1 = {
          id = 0;
          participant = testUser;
          stakes = [
            (govToken, { token = govToken; value = 100 }),
            (multiToken, { token = multiToken; value = 200 }),
          ];
          token = token1;
          proposedQuantity = { token = token1; value = 1000 };
          timestamp = Time.now();
          status = #Finalized;
          rejectionReason = null;
          adjustedQuantity = null;
          soldQuantity = null;
          executionPrice = null;
          positionId = null;
        };

        // Create submissions with precise quantities and deliberate ratios
        // User 1 submissions
        let submission1 = {
          baseSubmission1 with
          adjustedQuantity = ?{
            token = token1;
            value = 30_000;
          }
        };

        let submission2 = {
          baseSubmission1 with
          id = 1;
          token = token2;
          proposedQuantity = { token = token2; value = 1000 };
          adjustedQuantity = ?{
            token = token2;
            value = 15_000;
          };
        };

        // User 2 submissions
        let submission3 = {
          baseSubmission1 with
          id = 2;
          participant = testUser2;
          token = token1;
          proposedQuantity = { token = token1; value = 1000 };
          adjustedQuantity = ?{
            token = token1;
            value = 12_000;
          };
        };

        let submission4 = {
          baseSubmission1 with
          id = 3;
          participant = testUser2;
          token = token3;
          proposedQuantity = { token = token3; value = 1000 };
          adjustedQuantity = ?{
            token = token3;
            value = 8_000;
          };
        };

        let allSubmissions = [submission1, submission2, submission3, submission4];

        // Add tokens to stake accounts
        for (submission in allSubmissions.vals()) {
          switch (submission.adjustedQuantity) {
            case (?adjustedQuantity) {
              stakeAccounts.mint(submission.participant, adjustedQuantity);
            };
            case (null) {
              Debug.trap("Unexpected null adjustedQuantity");
            };
          };
          // Mint all stakes
          for ((_, amount) in submission.stakes.vals()) {
            stakeAccounts.mint(submission.participant, amount);
          };
        };

        // Create system stake with phantom positions for all three tokens
        let systemStake = {
          systemStakes = [
            (govToken, { token = govToken; value = 5_000 }),
            (multiToken, { token = multiToken; value = 3_000 }),
          ];
          phantomPositions = [
            (token1, { token = token1; value = 4_000 }),
            (token2, { token = token2; value = 2_000 }),
            (token3, { token = token3; value = 6_000 }),
          ];
        };

        // Create execution prices
        let executionPrices = coordinator.createExecutionPrices([
          {
            baseToken = token1;
            quoteToken = multiToken;
            value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() }; // 1.0
          },
          {
            baseToken = token2;
            quoteToken = multiToken;
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
            }; // 2.0
          },
          {
            baseToken = token3;
            quoteToken = multiToken;
            value = {
              value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 3;
            }; // 3.0
          },
        ]);

        // Execute first settlement
        let settlementRecord1 = coordinator.executeSettlement(
          allSubmissions,
          systemStake,
          executionPrices,
        );

        // Calculate expected values for phase 1
        // Token1: (30,000 + 12,000) * 1.0 = 42,000 Multi value
        // Token2: 15,000 * 2.0 = 30,000 Multi value
        // Token3: 8,000 * 3.0 = 24,000 Multi value
        // Total value: 96,000 Multi

        // Get token balances after settlement
        let token1Balance1 = userAccounts.getBalance(systemAccount, token1).value;
        let token2Balance1 = userAccounts.getBalance(systemAccount, token2).value;
        let token3Balance1 = userAccounts.getBalance(systemAccount, token3).value;

        // Verify expected balances match exactly
        expect.nat(token1Balance1).equal(30_000 + 12_000);
        expect.nat(token2Balance1).equal(15_000);
        expect.nat(token3Balance1).equal(8_000);

        // Verify backing tokens updated correctly
        let updatedBackingTokens1 = backingStore.getBackingTokens();
        let supplyUnit = backingStore.getSupplyUnit();
        let totalSupply1 = backingStore.getTotalSupply().value;
        let eta1 = totalSupply1 / supplyUnit;

        // Create a mapping from token to backing unit
        var token1Unit1 = 0;
        var token2Unit1 = 0;
        var token3Unit1 = 0;

        for (pair in updatedBackingTokens1.vals()) {
          if (Principal.equal(pair.token, token1)) {
            token1Unit1 := pair.backingUnit;
          } else if (Principal.equal(pair.token, token2)) {
            token2Unit1 := pair.backingUnit;
          } else if (Principal.equal(pair.token, token3)) {
            token3Unit1 := pair.backingUnit;
          };
        };

        // Verify token units match expected calculations
        expect.nat(token1Unit1).equal(token1Balance1 / eta1);
        expect.nat(token2Unit1).equal(token2Balance1 / eta1);
        expect.nat(token3Unit1).equal(token3Balance1 / eta1);

        // PHASE 2: Second settlement with additional tokens

        // Add more tokens to user accounts
        userAccounts.mint(testUser, { token = token2; value = 20_000 });
        userAccounts.mint(testUser2, { token = token3; value = 15_000 });

        // Create new submissions
        let submission5 = {
          baseSubmission1 with
          id = 4;
          token = token2;
          proposedQuantity = { token = token2; value = 1000 };
          adjustedQuantity = ?{
            token = token2;
            value = 20_000;
          };
        };

        let submission6 = {
          baseSubmission1 with
          id = 5;
          participant = testUser2;
          token = token3;
          proposedQuantity = { token = token3; value = 1000 };
          adjustedQuantity = ?{
            token = token3;
            value = 15_000;
          };
        };

        // Add tokens to stake accounts
        for ((_, amount) in submission5.stakes.vals()) {
          stakeAccounts.mint(testUser, amount);
        };
        switch (submission5.adjustedQuantity) {
          case (?adjustedQuantity) {
            stakeAccounts.mint(testUser, adjustedQuantity);
          };
          case (null) { Debug.trap("Unexpected null adjustedQuantity") };
        };

        for ((_, amount) in submission6.stakes.vals()) {
          stakeAccounts.mint(testUser2, amount);
        };
        switch (submission6.adjustedQuantity) {
          case (?adjustedQuantity) {
            stakeAccounts.mint(testUser2, adjustedQuantity);
          };
          case (null) { Debug.trap("Unexpected null adjustedQuantity") };
        };

        // Create new system stake with updated phantom positions
        let newSystemStake = {
          systemStakes = [
            (govToken, { token = govToken; value = 4_000 }),
            (multiToken, { token = multiToken; value = 2_000 }),
          ];
          phantomPositions = [
            (token1, { token = token1; value = 3_000 }),
            (token2, { token = token2; value = 4_000 }),
            (token3, { token = token3; value = 5_000 }),
          ];
        };

        // Execute second settlement
        let settlementRecord2 = coordinator.executeSettlement(
          [submission5, submission6],
          newSystemStake,
          executionPrices,
        );

        // Calculate expected values for phase 2
        // Token2: 20,000 * 2.0 = 40,000 Multi value
        // Token3: 15,000 * 3.0 = 45,000 Multi value
        // Total additional value: 85,000 Multi

        // Get final token balances
        let token1Balance2 = userAccounts.getBalance(systemAccount, token1).value;
        let token2Balance2 = userAccounts.getBalance(systemAccount, token2).value;
        let token3Balance2 = userAccounts.getBalance(systemAccount, token3).value;

        // Verify final balances
        expect.nat(token1Balance2).equal(token1Balance1); // Unchanged
        expect.nat(token2Balance2).equal(token2Balance1 + 20_000);
        expect.nat(token3Balance2).equal(token3Balance1 + 15_000);

        // Verify final backing tokens
        let updatedBackingTokens2 = backingStore.getBackingTokens();
        let totalSupply2 = backingStore.getTotalSupply().value;
        let eta2 = totalSupply2 / supplyUnit;

        // Create a mapping from token to backing unit for final state
        var token1Unit2 = 0;
        var token2Unit2 = 0;
        var token3Unit2 = 0;

        for (pair in updatedBackingTokens2.vals()) {
          if (Principal.equal(pair.token, token1)) {
            token1Unit2 := pair.backingUnit;
          } else if (Principal.equal(pair.token, token2)) {
            token2Unit2 := pair.backingUnit;
          } else if (Principal.equal(pair.token, token3)) {
            token3Unit2 := pair.backingUnit;
          };
        };

        // Verify final token units match expected calculations
        expect.nat(token1Unit2).equal(token1Balance2 / eta2);
        expect.nat(token2Unit2).equal(token2Balance2 / eta2);
        expect.nat(token3Unit2).equal(token3Balance2 / eta2);

        // Verify token value ratios are preserved in backing units
        // Token 1:2:3 value ratio should be 42,000 : 70,000 : 69,000
        // which with price factored in is 42,000 : 35,000 : 23,000
        // The backing units should maintain these proportions

        // Calculate ratios with enough precision (avoiding division)
        let unit1to2Ratio = token1Unit2 * 100_000 / token2Unit2;
        let unit1to3Ratio = token1Unit2 * 100_000 / token3Unit2;

        let balance1to2Ratio = (token1Balance2 / eta2) * 100_000 / (token2Balance2 / eta2);
        let balance1to3Ratio = (token1Balance2 / eta2) * 100_000 / (token3Balance2 / eta2);

        expect.nat(unit1to2Ratio).equal(balance1to2Ratio);
        expect.nat(unit1to3Ratio).equal(balance1to3Ratio);

        // Verify total supply reflects all minting operations
        let expectedTotalSupply = settlementRecord1.multiMinted.value + settlementRecord1.systemStakeMinted.value + settlementRecord2.multiMinted.value + settlementRecord2.systemStakeMinted.value;

        expect.nat(totalSupply2).equal(expectedTotalSupply);
      },
    );
  },
);
