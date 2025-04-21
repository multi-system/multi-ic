import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Time "mo:base/Time";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import SystemStakeTypes "../../../../multi_backend/types/SystemStakeTypes";
import SystemStakeOperations "../../../../multi_backend/competition/staking/SystemStakeOperations";
import CompetitionEntryStore "../../../../multi_backend/competition/CompetitionEntryStore";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import TokenUtils "../../../../multi_backend/financial/TokenUtils";
import CompetitionEntryTypes "../../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionTestUtils "../CompetitionTestUtils";

// Test suite for SystemStakeOperations
suite(
  "SystemStakeOperations Tests",
  func() {
    test(
      "calculateSystemStakes - basic test",
      func() {
        // Setup test data
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getTWENTY_PERCENT();
        };
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getFIFTY_PERCENT();
        };
        let totalGovStake : Nat = 1000;
        let totalMultiStake : Nat = 2000;
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = CompetitionTestUtils.getTestToken1(); backingUnit = 500 },
          { token = CompetitionTestUtils.getTestToken2(); backingUnit = 300 },
          { token = CompetitionTestUtils.getTestToken3(); backingUnit = 200 },
        ];

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify the basic structure and token types
        assert result.govSystemStake.token == CompetitionTestUtils.getGovToken();
        assert result.multiSystemStake.token == CompetitionTestUtils.getMultiToken();
        assert result.phantomPositions.size() == 3;

        // Verify the first phantom position
        let (phantom1Token, phantom1Amount) = result.phantomPositions[0];
        assert phantom1Token == CompetitionTestUtils.getTestToken1();
        assert phantom1Amount.token == CompetitionTestUtils.getTestToken1();

        // Verify the system stakes
        // Calculations:
        // For govSystemStake:
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * govMultiplier = 500 * 0.2 = 100

        // For multiSystemStake:
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(2000, 100) = 100
        // systemStake = effectiveStake * multiMultiplier = 100 * 0.5 = 50

        assert result.govSystemStake.value == 100;
        assert result.multiSystemStake.value == 50;
      },
    );

    test(
      "calculateSystemStakes - with volume limit higher than stakes",
      func() {
        // Setup test data with higher volume limit
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getTWENTY_PERCENT();
        };
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getFIFTY_PERCENT();
        };
        let totalGovStake : Nat = 100; // Lower than max stake at base rate
        let totalMultiStake : Nat = 50; // Lower than max stake at base rate
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify the system stakes
        // For govSystemStake:
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(100, 500) = 100
        // systemStake = effectiveStake * govMultiplier = 100 * 0.2 = 20

        // For multiSystemStake:
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(50, 100) = 50
        // systemStake = effectiveStake * multiMultiplier = 50 * 0.5 = 25

        assert result.govSystemStake.value == 20;
        assert result.multiSystemStake.value == 25;
      },
    );

    test(
      "calculateSystemStakes - with uneven backing distribution",
      func() {
        // Setup test data with highly skewed backing units
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getTWENTY_PERCENT();
        };
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getFIFTY_PERCENT();
        };
        let totalGovStake : Nat = 1000;
        let totalMultiStake : Nat = 2000;
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = CompetitionTestUtils.getTestToken1(); backingUnit = 800 }, // 80% of backing
          { token = CompetitionTestUtils.getTestToken2(); backingUnit = 150 }, // 15% of backing
          { token = CompetitionTestUtils.getTestToken3(); backingUnit = 50 }, // 5% of backing
        ];

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify the phantom positions
        assert result.phantomPositions.size() == 3;

        let (token1, amount1) = result.phantomPositions[0];
        let (token2, amount2) = result.phantomPositions[1];
        let (token3, amount3) = result.phantomPositions[2];

        assert token1 == CompetitionTestUtils.getTestToken1();
        assert token2 == CompetitionTestUtils.getTestToken2();
        assert token3 == CompetitionTestUtils.getTestToken3();

        // The values should be proportional to the backing units
        // Total backing units = 800 + 150 + 50 = 1000
        // Token1 proportion = 800/1000 = 0.8
        // Token2 proportion = 150/1000 = 0.15
        // Token3 proportion = 50/1000 = 0.05

        // Verify proportions are maintained (with small margin for integer division)
        let totalAmount = amount1.value + amount2.value + amount3.value;

        let token1Proportion = (amount1.value * 100) / totalAmount;
        let token2Proportion = (amount2.value * 100) / totalAmount;
        let token3Proportion = (amount3.value * 100) / totalAmount;

        // Allow a 1% margin of error due to integer division
        assert CompetitionTestUtils.natAbsDiff(token1Proportion, 80) <= 1;
        assert CompetitionTestUtils.natAbsDiff(token2Proportion, 15) <= 1;
        assert CompetitionTestUtils.natAbsDiff(token3Proportion, 5) <= 1;
      },
    );

    test(
      "calculateSystemStakes - with zero stakes",
      func() {
        // Setup test data with zero stakes
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getTWENTY_PERCENT();
        };
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getFIFTY_PERCENT();
        };
        let totalGovStake : Nat = 0;
        let totalMultiStake : Nat = 0;
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify the system stakes - both should be zero
        assert result.govSystemStake.value == 0;
        assert result.multiSystemStake.value == 0;

        // Phantom positions should still exist but with zero values
        assert result.phantomPositions.size() == 3;

        let (_, amount1) = result.phantomPositions[0];
        let (_, amount2) = result.phantomPositions[1];
        let (_, amount3) = result.phantomPositions[2];

        assert amount1.value == 0;
        assert amount2.value == 0;
        assert amount3.value == 0;
      },
    );

    test(
      "calculateSystemStakes - with zero backing units",
      func() {
        // Setup test data with empty backing pairs
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getTWENTY_PERCENT();
        };
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getFIFTY_PERCENT();
        };
        let totalGovStake : Nat = 1000;
        let totalMultiStake : Nat = 2000;
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [];

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify system stakes are calculated correctly
        assert result.govSystemStake.value == 100;
        assert result.multiSystemStake.value == 50;

        // Verify phantom positions are empty
        assert result.phantomPositions.size() == 0;
      },
    );

    test(
      "calculateSystemStakes - with very high multipliers",
      func() {
        // Setup test data with multipliers greater than 100%
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();
        let govMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
        }; // 200%
        let multiMultiplier : Types.Ratio = {
          value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 3;
        }; // 300%
        let totalGovStake : Nat = 1000;
        let totalMultiStake : Nat = 2000;
        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          govMultiplier,
          multiMultiplier,
          totalGovStake,
          totalMultiStake,
          volumeLimit,
          backingPairs,
        );

        // Verify the system stakes
        // For govSystemStake:
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * govMultiplier = 500 * 2.0 = 1000

        // For multiSystemStake:
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(2000, 100) = 100
        // systemStake = effectiveStake * multiMultiplier = 100 * 3.0 = 300

        assert result.govSystemStake.value == 1000;
        assert result.multiSystemStake.value == 300;
      },
    );
  },
);
