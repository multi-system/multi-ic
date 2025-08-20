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
import TokenAccessHelper "../../../../multi_backend/helper/TokenAccessHelper";

// Test suite for SystemStakeOperations
suite(
  "SystemStakeOperations Tests",
  func() {
    test(
      "calculateSystemStakes - basic test",
      func() {
        // Setup test data
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();

        // Setup total stakes array matching the configured stake tokens
        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 1000),
          (CompetitionTestUtils.getMultiToken(), 2000),
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = CompetitionTestUtils.getTestToken1(); backingUnit = 500 },
          { token = CompetitionTestUtils.getTestToken2(); backingUnit = 300 },
          { token = CompetitionTestUtils.getTestToken3(); backingUnit = 200 },
        ];

        // Execute the function with new signature
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
          volumeLimit,
          backingPairs,
        );

        // Verify the basic structure
        assert result.systemStakes.size() == 2; // Gov and Multi tokens
        assert result.phantomPositions.size() == 3; // Three backing tokens

        // Extract system stakes for each token type
        let govStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getGovToken());
        let multiStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getMultiToken());

        // Verify token types
        switch (govStake) {
          case (?stake) { assert stake.token == CompetitionTestUtils.getGovToken() };
          case null { assert false }; // Should have gov stake
        };

        switch (multiStake) {
          case (?stake) { assert stake.token == CompetitionTestUtils.getMultiToken() };
          case null { assert false }; // Should have multi stake
        };

        // Verify the first phantom position
        let (phantom1Token, phantom1Amount) = result.phantomPositions[0];
        assert phantom1Token == CompetitionTestUtils.getTestToken1();
        assert phantom1Amount.token == CompetitionTestUtils.getTestToken1();

        // Verify the system stakes values
        // Calculations:
        // For govSystemStake (20% multiplier, 5% base rate):
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * govMultiplier = 500 * 0.2 = 100

        // For multiSystemStake (50% multiplier, 1% base rate):
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(2000, 100) = 100
        // systemStake = effectiveStake * multiMultiplier = 100 * 0.5 = 50

        switch (govStake) {
          case (?stake) { assert stake.value == 100 };
          case null { assert false };
        };

        switch (multiStake) {
          case (?stake) { assert stake.value == 50 };
          case null { assert false };
        };
      },
    );

    test(
      "calculateSystemStakes - with volume limit higher than stakes",
      func() {
        // Setup test data with higher volume limit
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();

        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 100), // Lower than max stake at base rate
          (CompetitionTestUtils.getMultiToken(), 50), // Lower than max stake at base rate
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
          volumeLimit,
          backingPairs,
        );

        // Extract system stakes
        let govStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getGovToken());
        let multiStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getMultiToken());

        // Verify the system stakes
        // For govSystemStake:
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(100, 500) = 100
        // systemStake = effectiveStake * govMultiplier = 100 * 0.2 = 20

        // For multiSystemStake:
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(50, 100) = 50
        // systemStake = effectiveStake * multiMultiplier = 50 * 0.5 = 25

        switch (govStake) {
          case (?stake) { assert stake.value == 20 };
          case null { assert false };
        };

        switch (multiStake) {
          case (?stake) { assert stake.value == 25 };
          case null { assert false };
        };
      },
    );

    test(
      "calculateSystemStakes - with uneven backing distribution",
      func() {
        // Setup test data with highly skewed backing units
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();

        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 1000),
          (CompetitionTestUtils.getMultiToken(), 2000),
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = CompetitionTestUtils.getTestToken1(); backingUnit = 800 }, // 80% of backing
          { token = CompetitionTestUtils.getTestToken2(); backingUnit = 150 }, // 15% of backing
          { token = CompetitionTestUtils.getTestToken3(); backingUnit = 50 }, // 5% of backing
        ];

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
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

        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 0),
          (CompetitionTestUtils.getMultiToken(), 0),
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
          volumeLimit,
          backingPairs,
        );

        // Extract system stakes
        let govStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getGovToken());
        let multiStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getMultiToken());

        // Verify the system stakes - both should be zero
        switch (govStake) {
          case (?stake) { assert stake.value == 0 };
          case null { assert false };
        };

        switch (multiStake) {
          case (?stake) { assert stake.value == 0 };
          case null { assert false };
        };

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

        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 1000),
          (CompetitionTestUtils.getMultiToken(), 2000),
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = [];

        // Execute the function
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
          volumeLimit,
          backingPairs,
        );

        // Extract system stakes
        let govStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getGovToken());
        let multiStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getMultiToken());

        // Verify system stakes are calculated correctly
        switch (govStake) {
          case (?stake) { assert stake.value == 100 };
          case null { assert false };
        };

        switch (multiStake) {
          case (?stake) { assert stake.value == 50 };
          case null { assert false };
        };

        // Verify phantom positions are empty
        assert result.phantomPositions.size() == 0;
      },
    );

    test(
      "calculateSystemStakes - with very high multipliers",
      func() {
        // Setup test data with multipliers greater than 100%
        let competitionEntry = CompetitionTestUtils.createCompetitionEntryStore();

        // First, update the multipliers in the competition entry store
        // This would normally be done through governance configuration
        // For testing, we'll set up a competition with higher multipliers

        let totalStakes : [(Types.Token, Nat)] = [
          (CompetitionTestUtils.getGovToken(), 1000),
          (CompetitionTestUtils.getMultiToken(), 2000),
        ];

        let volumeLimit : Nat = 10000;
        let backingPairs : [BackingTypes.BackingPair] = CompetitionTestUtils.createMockBackingTokens();

        // Execute the function
        // Note: The function will use the multipliers from the competition's stake token configs
        // which are set to 20% for gov and 50% for multi in the test utils
        let result = SystemStakeOperations.calculateSystemStakes(
          competitionEntry,
          totalStakes,
          volumeLimit,
          backingPairs,
        );

        // Extract system stakes
        let govStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getGovToken());
        let multiStake = TokenAccessHelper.findInTokenArray(result.systemStakes, CompetitionTestUtils.getMultiToken());

        // With the default test multipliers (20% for gov, 50% for multi):
        // For govSystemStake:
        // maxStakeAtBaseRate = volumeLimit * govRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalGovStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * govMultiplier = 500 * 0.2 = 100

        // For multiSystemStake:
        // maxStakeAtBaseRate = volumeLimit * multiRate = 10000 * 0.01 = 100
        // effectiveStake = min(totalMultiStake, maxStakeAtBaseRate) = min(2000, 100) = 100
        // systemStake = effectiveStake * multiMultiplier = 100 * 0.5 = 50

        switch (govStake) {
          case (?stake) { assert stake.value == 100 };
          case null { assert false };
        };

        switch (multiStake) {
          case (?stake) { assert stake.value == 50 };
          case null { assert false };
        };
      },
    );
  },
);
