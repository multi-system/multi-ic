import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import { test; suite; expect } "mo:test";
import Nat "mo:base/Nat";
import Map "mo:base/HashMap";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import SystemStakeTypes "../../../multi_backend/types/SystemStakeTypes";
import SettlementTypes "../../../multi_backend/types/SettlementTypes";
import CompetitionStore "../../../multi_backend/competition/CompetitionStore";
import StakeVault "../../../multi_backend/competition/staking/StakeVault";
import CompetitionManager "../../../multi_backend/competition/CompetitionManager";
import FinalizeStakingRound "../../../multi_backend/competition/staking/FinalizeStakingRound";
import CompetitionTestUtils "./CompetitionTestUtils";
import BackingStore "../../../multi_backend/backing/BackingStore";
import BackingOperations "../../../multi_backend/backing/BackingOperations";
import SettlementCoordinator "../../../multi_backend/competition/settlement/SettlementCoordinator";

suite(
  "CompetitionManager Tests",
  func() {
    // Setup helper to create test environment for manager tests
    func setupManagerTest() : (
      CompetitionManager.CompetitionManager,
      CompetitionStore.CompetitionStore,
      StakeVault.StakeVault,
      Types.Account,
    ) {
      let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

      // Create a dummy settlement initiator that always succeeds
      let dummySettlementInitiator = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
        #ok(());
      };

      // Create a test CompetitionManager with required settlement initiator
      let manager = CompetitionManager.CompetitionManager(
        store,
        stakeVault,
        getCirculatingSupply,
        getBackingTokens,
        dummySettlementInitiator,
      );

      (manager, store, stakeVault, user);
    };

    test(
      "startStakingRound - starts round when inactive",
      func() {
        let (manager, store, _, _) = setupManagerTest();

        // Ensure competition is inactive
        store.setCompetitionActive(false);

        // Start staking round
        let result = manager.startStakingRound();

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(_)) {
            // Verify competition is now active
            assert store.isCompetitionActive();
          };
        };
      },
    );

    test(
      "startStakingRound - fails when already active",
      func() {
        let (manager, store, _, _) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Try to start again
        let result = manager.startStakingRound();

        // Verify error
        switch (result) {
          case (#err(#InvalidPhase(_))) {
            // Expected error
          };
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(_)) {
            Debug.print("Should have failed due to active competition");
            assert false;
          };
        };
      },
    );

    test(
      "acceptStakeRequest - processes request successfully",
      func() {
        let (manager, store, _, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Create stake request
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();
        let shouldQueue = false; // Process immediately

        // Submit stake request
        let result = manager.acceptStakeRequest(
          govStake,
          user,
          testToken,
          shouldQueue,
        );

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(output)) {
            assert output.submissionId == 0; // First submission
            assert output.isQueued == false; // Not queued
            assert output.tokenQuantity.value > 0; // Some tokens calculated
          };
        };
      },
    );

    test(
      "endStakingRound - finalizes and transitions state correctly",
      func() {
        let (manager, store, stakeVault, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Add a test submission to ensure there's something to finalize
        let id = store.generateSubmissionId();

        // Create a properly calculated submission with status ActiveRound
        let submission : SubmissionTypes.Submission = {
          id = id;
          participant = user;
          govStake = {
            token = CompetitionTestUtils.getGovToken();
            value = 5_000;
          };
          multiStake = {
            token = CompetitionTestUtils.getMultiToken();
            value = 1_000;
          };
          token = CompetitionTestUtils.getTestToken1();
          proposedQuantity = {
            token = CompetitionTestUtils.getTestToken1();
            value = 100_000;
          };
          timestamp = Time.now();
          status = #ActiveRound;
          rejectionReason = null;
          adjustedQuantity = null;
          soldQuantity = null;
          executionPrice = null;
          positionId = null;
        };

        // Add tokens to stake vault
        stakeVault.stake(user, submission.govStake);
        stakeVault.stake(user, submission.multiStake);
        stakeVault.stake(user, submission.proposedQuantity);

        // Add submission to store
        store.addSubmission(submission);

        // End staking round
        let result = manager.endStakingRound();

        // Verify result
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            assert false;
          };
          case (#ok(finalization)) {
            // Check competition is inactive
            assert (not store.isCompetitionActive());

            // Check submission is now PostRound - a key whitepaper requirement
            let postRoundSubmissions = store.getSubmissionsByStatus(#PostRound);
            assert (postRoundSubmissions.size() > 0);
          };
        };
      },
    );

    test(
      "getQueuedSubmissions - returns correct submissions",
      func() {
        let (manager, store, _, user) = setupManagerTest();

        // Set competition active
        store.setCompetitionActive(true);

        // Create and queue submissions
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };

        // Queue two submissions
        ignore manager.acceptStakeRequest(
          govStake,
          user,
          CompetitionTestUtils.getTestToken1(),
          true,
        );

        ignore manager.acceptStakeRequest(
          govStake,
          user,
          CompetitionTestUtils.getTestToken2(),
          true,
        );

        // Get queued submissions
        let queuedSubmissions = manager.getQueuedSubmissions();

        // Verify queue state
        assert queuedSubmissions.size() == 2;
        assert manager.getQueueSize() == 2;
      },
    );

    test(
      "endStakingRound - integrates with settlement process",
      func() {
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

        // Create tracking variables for settlement process
        var settlementCalled = false;
        var receivedSubmissions : [SubmissionTypes.Submission] = [];
        var receivedSystemStake : ?SystemStakeTypes.SystemStake = null;

        // Create mock settlement initiator
        let mockSettlementInitiator = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          settlementCalled := true;
          receivedSubmissions := output.finalizedSubmissions;
          receivedSystemStake := ?output.systemStake;
          #ok(());
        };

        // Create CompetitionManager with settlement initiator
        let manager = CompetitionManager.CompetitionManager(
          store,
          stakeVault,
          getCirculatingSupply,
          getBackingTokens,
          mockSettlementInitiator,
        );

        // Setup test submission
        store.setCompetitionActive(true);
        let id = store.generateSubmissionId();

        // Create a properly calculated submission with status ActiveRound
        let submission : SubmissionTypes.Submission = {
          id = id;
          participant = user;
          govStake = {
            token = CompetitionTestUtils.getGovToken();
            value = 5_000;
          };
          multiStake = {
            token = CompetitionTestUtils.getMultiToken();
            value = 1_000;
          };
          token = CompetitionTestUtils.getTestToken1();
          proposedQuantity = {
            token = CompetitionTestUtils.getTestToken1();
            value = 100_000;
          };
          timestamp = Time.now();
          status = #ActiveRound;
          rejectionReason = null;
          adjustedQuantity = null;
          soldQuantity = null;
          executionPrice = null;
          positionId = null;
        };

        // Add tokens to stake vault
        stakeVault.stake(user, submission.govStake);
        stakeVault.stake(user, submission.multiStake);
        stakeVault.stake(user, submission.proposedQuantity);

        // Add submission to store
        store.addSubmission(submission);

        // End staking round - should trigger settlement
        let result = manager.endStakingRound();

        // Verify settlement was called
        switch (result) {
          case (#err(e)) {
            Debug.print("Unexpected error: " # debug_show (e));
            expect.bool(false).isTrue(); // Will fail
          };
          case (#ok(_)) {
            // Verify settlement initiator was called
            expect.bool(settlementCalled).isTrue();

            // Verify submissions were passed to settlement
            expect.nat(receivedSubmissions.size()).equal(1);

            // Verify system stake was calculated and passed
            expect.bool(receivedSystemStake != null).isTrue();

            // Verify competition state changed
            expect.bool(store.isCompetitionActive()).isFalse();
          };
        };
      },
    );

    test(
      "settlement - from bids to settlement with backing updates",
      func() {
        // SETUP: Create test environment with backing tracking
        let (store, stakeVault, user, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();
        let user2 = CompetitionTestUtils.getUser2Principal();

        // Create backing store with precise, fixed supply unit for easier calculations
        let supplyUnit = 1000;
        let backingState : BackingTypes.BackingState = {
          var hasInitialized = false;
          var config = {
            supplyUnit = supplyUnit;
            totalSupply = 0;
            backingPairs = [];
            multiToken = CompetitionTestUtils.getMultiToken();
          };
        };

        let backingStore = BackingStore.BackingStore(backingState);
        backingStore.initialize(supplyUnit, CompetitionTestUtils.getMultiToken());

        // Add backing tokens that match our test tokens with precise initial backing units
        backingStore.updateBackingTokens([
          { token = CompetitionTestUtils.getTestToken1(); backingUnit = 10 },
          { token = CompetitionTestUtils.getTestToken2(); backingUnit = 20 },
          { token = CompetitionTestUtils.getTestToken3(); backingUnit = 30 },
        ]);

        // Record initial supply
        let initialSupply = backingStore.getTotalSupply().value;
        assert initialSupply == 0; // Verify it starts at zero

        // Create a virtual accounts system for the settlement phase
        let userAccounts = CompetitionTestUtils.createUserAccounts();

        // Create system account for settlement
        let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

        // Initial multi token balances
        let initialUserMulti = userAccounts.getBalance(user, CompetitionTestUtils.getMultiToken()).value;
        let initialUser2Multi = userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value;
        let initialSystemMulti = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value;

        // Create backing operations
        let backingOps = BackingOperations.BackingOperations(
          backingStore,
          userAccounts,
          systemAccount,
        );

        // Create settlement coordinator for the settlement phase
        let settlementCoordinator = SettlementCoordinator.SettlementCoordinator(
          userAccounts,
          stakeVault.getStakeAccounts(),
          backingOps,
          backingStore,
          CompetitionTestUtils.getGovToken(),
          systemAccount,
        );

        // Variables to track settlement outcomes
        var multiMintedForAcquisitions : Nat = 0;
        var systemStakeMinted : Nat = 0;

        // Create settlement initiator that uses our settlement coordinator
        let settlementInitiator = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
          // Create execution prices from competition prices
          let executionPrices = settlementCoordinator.createExecutionPrices(store.getCompetitionPrices());

          // Execute settlement
          let settlementRecord = settlementCoordinator.executeSettlement(
            output.finalizedSubmissions,
            output.systemStake,
            executionPrices,
          );

          // Capture settlement outcomes for verification
          multiMintedForAcquisitions := settlementRecord.multiMinted.value;
          systemStakeMinted := settlementRecord.systemStakeMinted.value;

          #ok(());
        };

        // Create CompetitionManager with settlement initiator
        let manager = CompetitionManager.CompetitionManager(
          store,
          stakeVault,
          getCirculatingSupply,
          getBackingTokens,
          settlementInitiator,
        );

        // PHASE 1: Start the competition and record initial state
        switch (manager.startStakingRound()) {
          case (#ok(_)) { /* Expected */ };
          case (#err(e)) {
            assert false;
          };
        };
        assert store.isCompetitionActive();

        // Record initial stake rates
        let initialGovRate = store.getGovRate().value;
        let initialMultiRate = store.getMultiRate().value;

        // PHASE 2: Submit multiple bids with precise quantities
        let token1 = CompetitionTestUtils.getTestToken1();
        let token2 = CompetitionTestUtils.getTestToken2();
        let token3 = CompetitionTestUtils.getTestToken3();
        let govToken = CompetitionTestUtils.getGovToken();

        // Get volumeLimit as defined in whitepaper (theta * circulating supply)
        let volumeLimit = store.getVolumeLimit(getCirculatingSupply);
        let circulatingSupply = getCirculatingSupply();

        // Use smaller stakes that will work with available balances
        let preciseLargeGovStake1 : Types.Amount = {
          token = govToken;
          value = 5_000; // Small enough for test balances
        };

        let preciseLargeGovStake2 : Types.Amount = {
          token = govToken;
          value = 2_500; // Half the first stake
        };

        // Submit stakes from both users for different tokens
        let result1 = manager.acceptStakeRequest(preciseLargeGovStake1, user, token1, false);
        let result2 = manager.acceptStakeRequest(preciseLargeGovStake2, user2, token2, false);

        // Capture the initial token quantities from submissions
        var initialToken1Quantity = 0;
        var initialToken2Quantity = 0;

        // Track submissions by ID
        var submission1Id : ?SubmissionTypes.SubmissionId = null;
        var submission2Id : ?SubmissionTypes.SubmissionId = null;

        switch (result1) {
          case (#ok(output)) {
            initialToken1Quantity := output.tokenQuantity.value;
            submission1Id := ?output.submissionId;
          };
          case (#err(e)) {
            assert false;
          };
        };

        switch (result2) {
          case (#ok(output)) {
            initialToken2Quantity := output.tokenQuantity.value;
            submission2Id := ?output.submissionId;
          };
          case (#err(e)) {
            assert false;
          };
        };

        // PHASE 3: Verify current rates haven't changed yet (they change during finalization)
        let currentGovRate = store.getGovRate().value;
        let currentMultiRate = store.getMultiRate().value;

        // Verify they're still the initial rates
        assert currentGovRate == initialGovRate;
        assert currentMultiRate == initialMultiRate;

        // PHASE 4: End the staking round and trigger settlement
        let finalizationResult = manager.endStakingRound();

        // Variables to store adjusted quantities from finalization
        var adjustedToken1Quantity = 0;
        var adjustedToken2Quantity = 0;

        switch (finalizationResult) {
          case (#ok(result)) {
            // Get the post-round submissions
            let postRoundSubmissions = store.getSubmissionsByStatus(#PostRound);

            // Get the actual adjusted quantities directly from finalized submissions
            for (submission in postRoundSubmissions.vals()) {
              switch (submission.adjustedQuantity) {
                case (null) {
                  assert false;
                };
                case (?adjQty) {
                  if (Principal.equal(submission.token, token1)) {
                    adjustedToken1Quantity := adjQty.value;
                  } else if (Principal.equal(submission.token, token2)) {
                    adjustedToken2Quantity := adjQty.value;
                  };
                };
              };
            };

            // Verify the quanity adjustments based on rate changes
            let finalGovRate = result.finalGovRate.value;
            let finalMultiRate = result.finalMultiRate.value;

            // If rates increased, quantities should decrease proportionally
            if (finalGovRate > initialGovRate) {
              // Check that adjusted quantities are smaller than initial ones
              assert adjustedToken1Quantity <= initialToken1Quantity;
              assert adjustedToken2Quantity <= initialToken2Quantity;

              // Verify rates meet requirement from whitepaper
              assert finalGovRate >= initialGovRate;
              assert finalMultiRate >= initialMultiRate;
            };
          };
          case (#err(e)) {
            assert false;
          };
        };

        // Verify competition is now inactive
        assert (not store.isCompetitionActive());

        // PHASE 5: Verify key settlement outcomes
        // Get all the updated tokens and supplies
        let updatedBackingTokens = backingStore.getBackingTokens();
        expect.nat(updatedBackingTokens.size()).equal(3);

        // Get token balances in system account after settlement
        let token1Balance = userAccounts.getBalance(systemAccount, token1).value;
        let token2Balance = userAccounts.getBalance(systemAccount, token2).value;
        let token3Balance = userAccounts.getBalance(systemAccount, token3).value;

        // Get total supply and calculate eta precisely
        let finalMultiSupply = backingStore.getTotalSupply().value;

        // Verify supply increased and meets the supply unit constraint
        assert finalMultiSupply > initialSupply;
        assert finalMultiSupply % supplyUnit == 0; // Must be a multiple of supply unit

        // Verify that the backing store's total supply equals the sum of tokens minted
        // during acquisition and system stake
        let totalNewSupply = multiMintedForAcquisitions + systemStakeMinted;

        // Allow for small rounding to nearest supply unit
        let supplyDiff = if (finalMultiSupply > totalNewSupply) {
          finalMultiSupply - totalNewSupply;
        } else {
          totalNewSupply - finalMultiSupply;
        };

        assert supplyDiff <= supplyUnit;

        let eta = finalMultiSupply / supplyUnit;

        // Map backing tokens to their units
        var token1Unit = 0;
        var token2Unit = 0;
        var token3Unit = 0;

        for (pair in updatedBackingTokens.vals()) {
          if (Principal.equal(pair.token, token1)) {
            token1Unit := pair.backingUnit;
          } else if (Principal.equal(pair.token, token2)) {
            token2Unit := pair.backingUnit;
          } else if (Principal.equal(pair.token, token3)) {
            token3Unit := pair.backingUnit;
          };
        };

        // Calculate the expected backing units with exact division
        let expectedToken1Unit = token1Balance / eta;
        let expectedToken2Unit = token2Balance / eta;

        // Verify backing units match expected calculations exactly
        assert token1Unit == expectedToken1Unit;
        assert token2Unit == expectedToken2Unit;

        // Verify backing unit ratios match token balance ratios with a small tolerance for rounding
        if (token1Balance > 0 and token2Balance > 0) {
          // Calculate the ratio equality
          let leftSide = token1Balance * token2Unit;
          let rightSide = token2Balance * token1Unit;

          // Calculate difference
          let diff = if (leftSide > rightSide) {
            leftSide - rightSide;
          } else {
            rightSide - leftSide;
          };

          // Calculate a tolerance - allow 1% deviation
          let tolerance = (leftSide + rightSide) / 200; // 0.5% of average

          // Assert with tolerance
          assert diff <= tolerance;
        };

        // PHASE 6: Verify Multi tokens were minted with exact calculation
        // Compute the token value from the prices and quantities
        let token1Price = switch (store.getCompetitionPrice(token1)) {
          case (?price) { price.value.value };
          case (null) { assert false; 0 }; // Should never happen
        };

        let token2Price = switch (store.getCompetitionPrice(token2)) {
          case (?price) { price.value.value };
          case (null) { assert false; 0 }; // Should never happen
        };

        // Calculate expected minted amounts
        let token1Value = token1Balance * token1Price / CompetitionTestUtils.getONE_HUNDRED_PERCENT();
        let token2Value = token2Balance * token2Price / CompetitionTestUtils.getONE_HUNDRED_PERCENT();

        // Get expected total token value - this needs to be rounded to the nearest supply unit multiple
        let rawExpectedTotalValue = token1Value + token2Value;
        let expectedAlignedValue = if (rawExpectedTotalValue % supplyUnit == 0) {
          rawExpectedTotalValue;
        } else {
          // Round up to next supply unit
          rawExpectedTotalValue + (supplyUnit - (rawExpectedTotalValue % supplyUnit));
        };

        // The finalMultiSupply should equal the aligned expected value
        // But we also need to account for systemStake minting
        // The simplest way to validate is to ensure the difference is exactly equivalent to system stake
        let systemStakeAmount = switch (finalizationResult) {
          case (#ok(result)) {
            result.systemStake.multiSystemStake.value;
          };
          case (#err(_)) { assert false; 0 };
        };

        // Align system stake amount to supply unit as well
        let alignedSystemStake = if (systemStakeAmount % supplyUnit == 0) {
          systemStakeAmount;
        } else {
          // Round up to next supply unit
          systemStakeAmount + (supplyUnit - (systemStakeAmount % supplyUnit));
        };

        // Allow for small rounding differences due to the multi-step process
        let totalExpectedValue = expectedAlignedValue + alignedSystemStake;
        let valueDifference = if (finalMultiSupply > totalExpectedValue) {
          finalMultiSupply - totalExpectedValue;
        } else {
          totalExpectedValue - finalMultiSupply;
        };

        // Tolerance should allow for rounding in supply unit alignment
        let tolerance = supplyUnit;

        assert valueDifference <= tolerance;

        // Get the updated multi token balances
        let finalUserMulti = userAccounts.getBalance(user, CompetitionTestUtils.getMultiToken()).value;
        let finalUser2Multi = userAccounts.getBalance(user2, CompetitionTestUtils.getMultiToken()).value;
        let finalSystemMulti = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value;

        // Calculate increases in Multi tokens
        let userMultiIncrease = finalUserMulti - initialUserMulti;
        let user2MultiIncrease = finalUser2Multi - initialUser2Multi;
        let systemMultiIncrease = finalSystemMulti - initialSystemMulti;

        // Calculate total multi tokens in the system and compare to backing store supply
        let multiTokenSupply = finalUserMulti + finalUser2Multi + finalSystemMulti;

        // Verify the totals with test environment context
        if (multiTokenSupply != finalMultiSupply) {
          let diff = if (multiTokenSupply > finalMultiSupply) {
            multiTokenSupply - finalMultiSupply;
          } else {
            finalMultiSupply - multiTokenSupply;
          };

          // The difference should be the initial balance from test setup
          let initialTestBalance = initialUserMulti + initialUser2Multi + initialSystemMulti;

          // Verify that the difference in balances is close to the initial test balance
          let bdiff = if (diff > initialTestBalance) {
            diff - initialTestBalance;
          } else {
            initialTestBalance - diff;
          };

          // Allow a small tolerance for rounding
          assert bdiff <= 1000; // 1 supply unit tolerance
        };
      },
    );
  },
);
