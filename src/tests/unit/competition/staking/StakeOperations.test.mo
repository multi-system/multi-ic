import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import StakeOperations "../../../../multi_backend/competition/staking/StakeOperations";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Stake Operations",
  func() {
    // Setup test environment for each test
    let setupTest = func() : CompetitionEntryStore.CompetitionEntryStore {
      let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
      competitionEntry.updateStatus(#AcceptingStakes);
      competitionEntry;
    };

    // Test calculateSubmission function
    test(
      "calculateSubmission - returns correct quantities for valid input",
      func() {
        let competitionEntry = setupTest();

        // Create test inputs
        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        // Call the function under test
        let result = StakeOperations.calculateSubmission(
          competitionEntry,
          govStake,
          testToken,
        );

        // Verify the result
        switch (result) {
          case (#err(error)) {
            Debug.print("Unexpected error: " # debug_show (error));
            assert (false); // Should not fail
          };
          case (#ok(quantities)) {
            // Verify gov stake is passed through unchanged
            assert (quantities.govStake.value == govStake.value);
            assert (Principal.equal(quantities.govStake.token, govStake.token));

            // Verify multi stake calculation:
            // For 5% gov rate and 1% multi rate, the conversion should be:
            // govStake * (multiRate/govRate) = 1000 * (1%/5%) = 1000 * 0.2 = 200
            assert (quantities.multiStake.value == 200);
            assert (Principal.equal(quantities.multiStake.token, CompetitionTestUtils.getMultiToken()));

            // Verify token quantity calculation using the price from test utils
            // Token price should be 1.0 Multi tokens per test token
            // So formula is: multiStake / (multiRate * price) = 200 / (1% * 1.0) = 200 / 0.01 = 20,000
            assert (quantities.tokenQuantity.value == 20_000);
            assert (Principal.equal(quantities.tokenQuantity.token, testToken));
            assert (Principal.equal(quantities.proposedToken, testToken));
          };
        };
      },
    );

    test(
      "calculateSubmission - returns error when competition inactive",
      func() {
        let competitionEntry = setupTest();
        competitionEntry.updateStatus(#PreAnnouncement);

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = StakeOperations.calculateSubmission(
          competitionEntry,
          govStake,
          testToken,
        );

        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InvalidPhase(_))) {
            // Expected error - in the new architecture, we get InvalidPhase instead of CompetitionNotActive
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "calculateSubmission - returns error for unapproved token",
      func() {
        let competitionEntry = setupTest();

        let govStake : Types.Amount = {
          token = CompetitionTestUtils.getGovToken();
          value = 1000;
        };

        // Use a principal that's not in the approved token list
        let unapprovedToken = Principal.fromText("aaaaa-aa");

        let result = StakeOperations.calculateSubmission(
          competitionEntry,
          govStake,
          unapprovedToken,
        );

        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#TokenNotApproved(token))) {
            assert (Principal.equal(token, unapprovedToken));
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    test(
      "calculateSubmission - validates token type",
      func() {
        let competitionEntry = setupTest();

        // Create invalid gov stake with wrong token
        let invalidGovStake : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken(); // Wrong token for gov stake
          value = 1000;
        };
        let testToken = CompetitionTestUtils.getTestToken1();

        let result = StakeOperations.calculateSubmission(
          competitionEntry,
          invalidGovStake,
          testToken,
        );

        // Should return error for invalid token type
        switch (result) {
          case (#ok(_)) {
            assert (false); // Should not succeed
          };
          case (#err(#InvalidSubmission(_))) {
            // Expected error
          };
          case (#err(error)) {
            Debug.print("Unexpected error type: " # debug_show (error));
            assert (false); // Wrong error type
          };
        };
      },
    );

    // Test updateAdjustedStakeRates function
    test(
      "updateAdjustedStakeRates - updates rates correctly when below volume limit",
      func() {
        let competitionEntry = setupTest();

        // Initial rates from test utils: govRate = 5%, multiRate = 1%
        let initialGovRate = competitionEntry.getGovRate();
        let initialMultiRate = competitionEntry.getMultiRate();

        // Set total stakes to 1% of volume limit
        let volumeLimit = 1_000_000; // from test utils (20% of 5,000,000)
        let totalGovStake = volumeLimit / 100; // 1% of volume limit
        let totalMultiStake = volumeLimit / 100; // 1% of volume limit

        // Call function under test
        let (updatedGovRate, updatedMultiRate) = StakeOperations.updateAdjustedStakeRates(
          competitionEntry,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
        );

        // Rates should remain unchanged since stakes are below volume limit
        assert (updatedGovRate.value == initialGovRate.value);
        assert (updatedMultiRate.value == initialMultiRate.value);

        // Check the adjusted rates (not base rates)
        assert (competitionEntry.getAdjustedGovRate().value == initialGovRate.value);
        assert (competitionEntry.getAdjustedMultiRate().value == initialMultiRate.value);
      },
    );

    test(
      "updateAdjustedStakeRates - increases rates when above volume limit",
      func() {
        let competitionEntry = setupTest();

        // Initial rates from test utils: govRate = 5%, multiRate = 1%
        let initialGovRate = competitionEntry.getGovRate();
        let initialMultiRate = competitionEntry.getMultiRate();

        // Set total stakes to 80% of volume limit
        let volumeLimit = 1_000_000; // from test utils
        let totalGovStake = 800_000; // 80% of volume limit
        let totalMultiStake = 800_000; // 80% of volume limit

        // Expected values: max(currentRate, totalStake/volumeLimit)
        let expectedRate = RatioOperations.fromNats(totalGovStake, volumeLimit); // 800,000/1,000,000 = 80%

        // Call function under test
        let (updatedGovRate, updatedMultiRate) = StakeOperations.updateAdjustedStakeRates(
          competitionEntry,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
        );

        // Rates should increase since stakes are above current rates (5% and 1%)
        assert (updatedGovRate.value == expectedRate.value);
        assert (updatedMultiRate.value == expectedRate.value);

        // Check the adjusted rates (not base rates)
        assert (competitionEntry.getAdjustedGovRate().value == expectedRate.value);
        assert (competitionEntry.getAdjustedMultiRate().value == expectedRate.value);
      },
    );

    test(
      "updateAdjustedStakeRates - never decreases rates",
      func() {
        let competitionEntry = setupTest();

        // First, increase rates to 80%
        let volumeLimit = 1_000_000;
        let highStake = 800_000; // 80% of limit
        let (highGovRate, highMultiRate) = StakeOperations.updateAdjustedStakeRates(
          competitionEntry,
          highStake,
          highStake,
          volumeLimit,
        );

        // Then call with lower stakes (10%)
        let lowStake = 100_000; // 10% of limit
        let (newGovRate, newMultiRate) = StakeOperations.updateAdjustedStakeRates(
          competitionEntry,
          lowStake,
          lowStake,
          volumeLimit,
        );

        // Rates should remain at 80% even though stakes decreased
        assert (newGovRate.value == highGovRate.value);
        assert (newMultiRate.value == highMultiRate.value);

        // Check the adjusted rates (not base rates)
        assert (competitionEntry.getAdjustedGovRate().value == highGovRate.value);
        assert (competitionEntry.getAdjustedMultiRate().value == highMultiRate.value);
      },
    );

    // Test calculateAdjustedStakeRate function (separate from store updates)
    test(
      "calculateAdjustedStakeRate - calculates correct rate for gov token",
      func() {
        let competitionEntry = setupTest();
        let volumeLimit = 1_000_000;

        // Test with 50% of volume limit
        let totalStake = 500_000;
        let isGovToken = true;

        let calculatedRate = StakeOperations.calculateAdjustedStakeRate(
          competitionEntry,
          isGovToken,
          totalStake,
          volumeLimit,
        );

        // Expected: max(5%, 50%) = 50%
        let expectedRate = RatioOperations.fromNats(totalStake, volumeLimit);
        assert (calculatedRate.value == expectedRate.value);

        // Store should not be affected by this calculation
        assert (competitionEntry.getGovRate().value == CompetitionTestUtils.getFIVE_PERCENT());
      },
    );

    test(
      "calculateAdjustedStakeRate - calculates correct rate for multi token",
      func() {
        let competitionEntry = setupTest();
        let volumeLimit = 1_000_000;

        // Test with 0.5% of volume limit (below current rate)
        let totalStake = 5_000;
        let isGovToken = false;

        let calculatedRate = StakeOperations.calculateAdjustedStakeRate(
          competitionEntry,
          isGovToken,
          totalStake,
          volumeLimit,
        );

        // Expected: max(1%, 0.5%) = 1%
        let expectedRate = competitionEntry.getMultiRate(); // Should remain at 1%
        assert (calculatedRate.value == expectedRate.value);

        // Store should not be affected
        assert (competitionEntry.getMultiRate().value == CompetitionTestUtils.getONE_PERCENT());
      },
    );
  },
);
