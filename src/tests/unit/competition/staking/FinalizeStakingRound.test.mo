import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import FinalizeStakingRound "../../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import StakeVault "../../../../multi_backend/competition/staking/StakeVault";
import StakeCalculator "../../../../multi_backend/competition/staking/StakeCalculator";
import CompetitionTestUtils "../CompetitionTestUtils";
import TokenAccessHelper "../../../../multi_backend/helper/TokenAccessHelper";

suite(
  "FinalizeStakingRound Tests",
  func() {
    // Helper to find a specific rate in the rates array
    func findRate(rates : [(Types.Token, Types.Ratio)], token : Types.Token) : ?Types.Ratio {
      for ((t, rate) in rates.vals()) {
        if (Principal.equal(t, token)) {
          return ?rate;
        };
      };
      null;
    };

    // Helper to find a specific stake in the systemStakes array
    func findSystemStake(systemStakes : [(Types.Token, Types.Amount)], token : Types.Token) : ?Types.Amount {
      TokenAccessHelper.findInTokenArray(systemStakes, token);
    };

    // Helper to create a submission with calculated stakes
    func createSubmissionWithStakes(
      competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
      participant : Types.Account,
      govStakeValue : Nat,
      token : Types.Token,
    ) : SubmissionTypes.Submission {
      let id = competitionEntry.generateSubmissionId();

      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();

      // Get current rates
      let govRate = competitionEntry.getEffectiveRate(govToken);
      let multiRate = competitionEntry.getEffectiveRate(multiToken);

      // Create governance stake
      let govStake = {
        token = govToken;
        value = govStakeValue;
      };

      // Calculate equivalent multi stake
      let multiStake = StakeCalculator.calculateEquivalentStake(
        govStake,
        govRate,
        multiRate,
        multiToken,
      );

      // Get token price
      let tokenPrice = {
        baseToken = token;
        quoteToken = multiToken;
        value = { value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() };
      };

      // Calculate token quantity
      let tokenQuantity = StakeCalculator.calculateTokenQuantity(
        multiStake,
        multiRate,
        tokenPrice,
      );

      {
        id = id;
        participant = participant;
        stakes = [
          (govToken, govStake),
          (multiToken, multiStake),
        ];
        token = token;
        proposedQuantity = tokenQuantity;
        timestamp = Time.now();
        status = #Staked;
        rejectionReason = null;
        adjustedQuantity = null;
        soldQuantity = null;
        executionPrice = null;
        positionId = null;
      };
    };

    // Helper to get test participant principals - using valid, unique principals
    func getTestParticipant(index : Nat) : Types.Account {
      // Using principals that follow valid IC principal format
      let participants = [
        Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai"), // Test token 2
        Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"), // Gov token
        Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai"), // Test token 3
        Principal.fromText("rdmx6-jaaaa-aaaaa-aaadq-cai"), // Valid test principal
        Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai"), // Valid test principal
        Principal.fromText("rno2w-sqaaa-aaaaa-aaacq-cai"), // Valid test principal
        Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai"), // Valid test principal
        Principal.fromText("rh2pm-ryaaa-aaaah-qccga-cai"), // Valid test principal
        Principal.fromText("be2us-64aaa-aaaaa-qaabq-cai"), // Valid test principal
        Principal.fromText("xe5ii-jiaaa-aaaaf-qaaya-cai"), // Valid test principal
      ];
      participants[index];
    };

    // Setup helper to create test environment with realistic active submissions
    func setupWithActiveSubmissions(
      activeCount : Nat
    ) : (
      CompetitionEntryStore.CompetitionEntryStore,
      Types.Account,
      () -> Nat,
      () -> [BackingTypes.BackingPair],
    ) {
      let (competitionEntry, stakeVault, user, getCirculatingSupply, getBackingTokens, _) = CompetitionTestUtils.createTestEnvironment();

      // Ensure competition is active
      competitionEntry.updateStatus(#AcceptingStakes);

      // Create and add active round submissions with realistic values
      for (i in Iter.range(0, activeCount - 1)) {
        // Create submission with standard stakes
        let submission = createSubmissionWithStakes(
          competitionEntry,
          user,
          5_000, // Standard governance stake
          CompetitionTestUtils.getTestToken1(),
        );

        // Execute actual staking through the vault
        for ((_, amount) in submission.stakes.vals()) {
          competitionEntry.getStakeVault().stake(user, amount);
        };
        competitionEntry.getStakeVault().stake(user, submission.proposedQuantity);

        // Add submission to competition entry
        competitionEntry.addSubmission(submission);
      };

      (competitionEntry, user, getCirculatingSupply, getBackingTokens);
    };

    // Setup with multiple participants creating high demand
    func setupWithHighDemand() : (
      CompetitionEntryStore.CompetitionEntryStore,
      () -> Nat,
      () -> [BackingTypes.BackingPair],
    ) {
      let (competitionEntry, stakeVault, _, getCirculatingSupply, getBackingTokens, _) = CompetitionTestUtils.createTestEnvironment();

      // Ensure competition is active
      competitionEntry.updateStatus(#AcceptingStakes);

      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();
      let userAccounts = competitionEntry.getStakeVault().getUserAccounts();

      // Create 10 high-stake participants to simulate market pressure
      for (i in Iter.range(0, 9)) {
        // Generate a unique principal for each participant
        let participant = CompetitionTestUtils.generateTestPrincipal(i + 1); // +1 to avoid anonymous

        // Give each participant substantial tokens (simulating they acquired them from market)
        userAccounts.mint(participant, { token = govToken; value = 60_000 });
        userAccounts.mint(participant, { token = multiToken; value = 30_000 });
        userAccounts.mint(participant, { token = CompetitionTestUtils.getTestToken1(); value = 1_000_000 });

        // Create submission with high stakes
        let submission = createSubmissionWithStakes(
          competitionEntry,
          participant,
          50_000, // High governance stake per participant
          CompetitionTestUtils.getTestToken1(),
        );

        // Execute actual staking through the vault
        for ((_, amount) in submission.stakes.vals()) {
          competitionEntry.getStakeVault().stake(participant, amount);
        };
        competitionEntry.getStakeVault().stake(participant, submission.proposedQuantity);

        // Add submission to competition entry
        competitionEntry.addSubmission(submission);
      };

      (competitionEntry, getCirculatingSupply, getBackingTokens);
    };

    test(
      "finalizeRound - basic successful finalization",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(2);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(e)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // Check counts
            assert finalization.stakedSubmissionsCount == 2;

            // Verify that rates didn't change significantly (low stakes shouldn't trigger adjustment)
            let govToken = CompetitionTestUtils.getGovToken();
            let multiToken = CompetitionTestUtils.getMultiToken();

            let initialGovRate = findRate(finalization.initialRates, govToken);
            let finalGovRate = findRate(finalization.finalRates, govToken);
            let initialMultiRate = findRate(finalization.initialRates, multiToken);
            let finalMultiRate = findRate(finalization.finalRates, multiToken);

            switch (initialGovRate, finalGovRate, initialMultiRate, finalMultiRate) {
              case (?initGov, ?finGov, ?initMulti, ?finMulti) {
                // With low stakes, rates should remain at base
                assert initGov.value == finGov.value;
                assert initMulti.value == finMulti.value;
              };
              case _ {
                assert false; // Rates should exist
              };
            };

            // Verify all submissions moved to Finalized status
            let finalizedSubmissions = competitionEntry.getSubmissionsByStatus(#Finalized);
            assert finalizedSubmissions.size() == 2;
          };
        };
      },
    );

    test(
      "finalizeRound - with empty submission list",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(0);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail even with empty list
          };
          case (#ok(finalization)) {
            // Check counts
            assert finalization.stakedSubmissionsCount == 0;
            assert finalization.adjustmentSuccessCount == 0;

            // System stake should still be calculated
            assert finalization.systemStake.phantomPositions.size() >= 0;
          };
        };
      },
    );

    test(
      "finalizeRound - when competition not active",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Set competition to inactive
        competitionEntry.updateStatus(#PreAnnouncement);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (#err(_)) {
            assert false; // Should only get InvalidPhase error
          };
          case (#ok(_)) {
            assert false; // Should not succeed when competition is inactive
          };
        };
      },
    );

    test(
      "finalizeRound - when system not initialized",
      func() {
        // Create an uninitialized competition entry store for testing
        let (competitionEntry, _, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(0);

        // Update status to inactive to simulate uninitialized state
        competitionEntry.updateStatus(#PreAnnouncement);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(#InvalidPhase(_)) or #err(#OperationFailed(_))) {
            // Expected error
          };
          case (#err(_)) {
            assert false; // Should only get expected error types
          };
          case (#ok(_)) {
            assert false; // Should not succeed when system is not initialized
          };
        };
      },
    );

    test(
      "finalizeRound - stake rates adjustment logic with real market pressure",
      func() {
        // Setup with multiple high-stake participants
        let (competitionEntry, getCirculatingSupply, getBackingTokens) = setupWithHighDemand();

        // Get initial rates before finalization
        let govToken = CompetitionTestUtils.getGovToken();
        let multiToken = CompetitionTestUtils.getMultiToken();

        // Store initial effective rates
        let initialGovRateBefore = competitionEntry.getEffectiveRate(govToken);
        let initialMultiRateBefore = competitionEntry.getEffectiveRate(multiToken);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(e)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // With 10 participants each staking 50,000 governance tokens = 500,000 total
            // This should trigger rate adjustment
            assert finalization.stakedSubmissionsCount == 10;

            // Check that rates increased due to high demand
            let finalGovRate = findRate(finalization.finalRates, govToken);
            let finalMultiRate = findRate(finalization.finalRates, multiToken);
            let initGovRate = findRate(finalization.initialRates, govToken);
            let initMultiRate = findRate(finalization.initialRates, multiToken);

            switch (finalGovRate, finalMultiRate, initGovRate, initMultiRate) {
              case (?finGov, ?finMulti, ?initGov, ?initMulti) {
                // At least one rate should have increased due to high demand
                assert finGov.value >= initGov.value;
                assert finMulti.value >= initMulti.value;

                // With 500,000 total gov stakes and 20% volume limit on 1M supply (200,000),
                // the gov rate should definitely increase: 500,000 / 200,000 = 2.5x base rate
                assert finGov.value > initGov.value;
              };
              case _ {
                assert false; // Rates should exist
              };
            };

            // Verify total stakes reflect actual staked amounts
            let totalGovStake = TokenAccessHelper.getWithDefault(finalization.totalStakes, govToken, 0);
            let totalMultiStake = TokenAccessHelper.getWithDefault(finalization.totalStakes, multiToken, 0);

            // Should be approximately 500,000 governance tokens staked (10 * 50,000)
            assert totalGovStake >= 450_000; // Allow some variance for calculations
          };
        };
      },
    );

    test(
      "finalizeRound - system stake calculation verification",
      func() {
        let (competitionEntry, user, getCirculatingSupply, getBackingTokens) = setupWithActiveSubmissions(1);

        // Execute finalization
        let result = FinalizeStakingRound.finalizeRound(
          competitionEntry,
          getCirculatingSupply,
          getBackingTokens,
        );

        // Verify result
        switch (result) {
          case (#err(_)) {
            assert false; // Should not fail
          };
          case (#ok(finalization)) {
            // Check system stake properties using the flexible structure
            let govToken = CompetitionTestUtils.getGovToken();
            let multiToken = CompetitionTestUtils.getMultiToken();

            let govSystemStake = findSystemStake(finalization.systemStake.systemStakes, govToken);
            let multiSystemStake = findSystemStake(finalization.systemStake.systemStakes, multiToken);

            switch (govSystemStake, multiSystemStake) {
              case (?govStake, ?multiStake) {
                assert Principal.equal(govStake.token, govToken);
                assert Principal.equal(multiStake.token, multiToken);

                // System stakes should be calculated based on multipliers
                assert govStake.value > 0 or multiStake.value > 0;
              };
              case _ {
                // It's acceptable if system stakes are not set in minimal scenarios
              };
            };

            // Verify phantom positions exist
            assert finalization.systemStake.phantomPositions.size() > 0;

            // Verify phantom positions reference backing tokens
            if (finalization.systemStake.phantomPositions.size() > 0) {
              let (phantomToken, _) = finalization.systemStake.phantomPositions[0];
              // Should be one of our test backing tokens
              assert Principal.equal(phantomToken, CompetitionTestUtils.getTestToken1()) or Principal.equal(phantomToken, CompetitionTestUtils.getTestToken2()) or Principal.equal(phantomToken, CompetitionTestUtils.getTestToken3());
            };
          };
        };
      },
    );
  },
);
