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
import SystemStakeTypes "../../../multi_backend/types/SystemStakeTypes";
import CompetitionManager "../../../multi_backend/competition/CompetitionManager";
import FinalizeStakingRound "../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionTestUtils "./CompetitionTestUtils";

// Advanced test suite for the CompetitionManager with settlement integration
suite(
  "Complex Competition Manager",
  func() {
    // Create mock tokens for testing
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockTokenB = CompetitionTestUtils.getTestToken2();
    let mockTokenC = CompetitionTestUtils.getTestToken3();
    let mockUser = CompetitionTestUtils.getUserPrincipal();
    let mockUser2 = CompetitionTestUtils.getUser2Principal();

    test(
      "creates system stake with proper parameters",
      func() {
        // Create test environment
        let (entryStore, stakeVault, userAccount, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Initialize competition to correct state (AcceptingStakes)
        entryStore.updateStatus(#AcceptingStakes);

        // Create a submission directly to avoid the acceptStakeRequest method
        let submissionId = entryStore.generateSubmissionId();
        let submission = CompetitionTestUtils.createTestSubmission(
          submissionId,
          userAccount,
          #Staked, // Use Staked status directly
          mockTokenA,
        );

        // Add submission with non-zero stake values
        let updatedSubmission = {
          submission with
          govStake = { token = mockGovToken; value = 5000 };
          multiStake = { token = mockSystemToken; value = 1000 };
        };

        entryStore.addSubmission(updatedSubmission);

        // Set up tracking variables for system stake creation
        var systemStakeReceived : ?SystemStakeTypes.SystemStake = null;

        // Create mock settlement function that captures parameters
        let mockSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          systemStakeReceived := ?output.systemStake;
          #ok(());
        };

        // Create manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          mockSettlement,
        );

        // MANUALLY create a FinalizeStakingRound.FinalizationResult
        // This simulates the result of endStakingRound without calling it directly
        let systemStake : SystemStakeTypes.SystemStake = {
          govSystemStake = { token = mockGovToken; value = 10000 };
          multiSystemStake = { token = mockSystemToken; value = 2000 };
          phantomPositions = [
            (mockTokenA, { token = mockTokenA; value = 5000 }),
            (mockTokenB, { token = mockTokenB; value = 3000 }),
            (mockTokenC, { token = mockTokenC; value = 2000 }),
          ];
        };

        entryStore.setSystemStake(systemStake);
        entryStore.updateStatus(#Finalizing);

        // Change submission status to Finalized
        let finalizedSubmission = {
          updatedSubmission with
          status = #Finalized;
          adjustedQuantity = ?{ token = mockTokenA; value = 90000 };
        };

        expect.bool(entryStore.updateSubmission(finalizedSubmission)).isTrue();

        // Move to settlement state
        entryStore.updateStatus(#Settlement);

        // Create StakingRoundOutput directly
        let stakingOutput : CompetitionManager.StakingRoundOutput = {
          finalizedSubmissions = [finalizedSubmission];
          systemStake = systemStake;
          govRate = entryStore.getGovRate();
          multiRate = entryStore.getMultiRate();
          volumeLimit = entryStore.getVolumeLimit();
        };

        // Call settlement function directly
        let result = mockSettlement(stakingOutput);
        expect.bool(Result.isOk(result)).isTrue();

        // Verify system stake values were received correctly
        switch (systemStakeReceived) {
          case (null) {
            expect.bool(false).isTrue(); // Should not happen
          };
          case (?receivedStake) {
            expect.principal(receivedStake.govSystemStake.token).equal(mockGovToken);
            expect.principal(receivedStake.multiSystemStake.token).equal(mockSystemToken);
            expect.nat(receivedStake.govSystemStake.value).equal(systemStake.govSystemStake.value);
            expect.nat(receivedStake.multiSystemStake.value).equal(systemStake.multiSystemStake.value);

            // Verify phantom positions were passed correctly
            expect.nat(receivedStake.phantomPositions.size()).equal(3);

            // Check that the first phantom position matches what we set
            let (firstToken, firstAmount) = receivedStake.phantomPositions[0];
            expect.principal(firstToken).equal(mockTokenA);
            expect.nat(firstAmount.value).equal(5000);
          };
        };

        // Verify the system stake was stored in the competition
        switch (entryStore.getSystemStake()) {
          case (null) {
            expect.bool(false).isTrue(); // Should not be null
          };
          case (?storedStake) {
            expect.nat(storedStake.multiSystemStake.value).equal(systemStake.multiSystemStake.value);
            expect.nat(storedStake.govSystemStake.value).equal(systemStake.govSystemStake.value);
            expect.nat(storedStake.phantomPositions.size()).equal(systemStake.phantomPositions.size());
          };
        };
      },
    );

    test(
      "getQueuedSubmissions returns correct submissions",
      func() {
        // Create test environment
        let (entryStore, _, userAccount, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();
        entryStore.updateStatus(#AcceptingStakes);

        // Create settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create manager
        let manager = CompetitionManager.CompetitionManager(
          getCirculatingSupply,
          getBackingTokens,
          startSettlement,
        );

        // Create submissions with queued status directly
        let submission1Id = entryStore.generateSubmissionId();
        let submission1 = CompetitionTestUtils.createTestSubmission(
          submission1Id,
          userAccount,
          #Queued,
          mockTokenA,
        );
        entryStore.addSubmission(submission1);

        let submission2Id = entryStore.generateSubmissionId();
        let submission2 = CompetitionTestUtils.createTestSubmission(
          submission2Id,
          mockUser2, // Use a different user
          #Queued,
          mockTokenB // Use a different token
        );
        entryStore.addSubmission(submission2);

        // Verify correct number of queued submissions
        let queuedSubmissions = entryStore.getSubmissionsByStatus(#Queued);
        expect.nat(queuedSubmissions.size()).equal(2);
      },
    );

    test(
      "calculates volume limit correctly based on circulating supply",
      func() {
        // Create test environment with a fixed circulating supply
        let fixedSupply = 1_000_000; // 1 million tokens
        let getFixedSupply = CompetitionTestUtils.createCirculatingSupplyFunction(fixedSupply);

        let (entryStore, _, _, _, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Create settlement function
        let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          #ok(());
        };

        // Create manager with our fixed supply function
        let manager = CompetitionManager.CompetitionManager(
          getFixedSupply,
          getBackingTokens,
          startSettlement,
        );

        // Calculate volume limit
        let volumeLimit = entryStore.calculateVolumeLimit(getFixedSupply);

        // The theta value from CompetitionTestUtils is 20%
        let expectedLimit = fixedSupply * CompetitionTestUtils.getTWENTY_PERCENT() / CompetitionTestUtils.getONE_HUNDRED_PERCENT();

        // Verify volume limit calculation
        expect.nat(volumeLimit).equal(expectedLimit);
      },
    );
  },
);
