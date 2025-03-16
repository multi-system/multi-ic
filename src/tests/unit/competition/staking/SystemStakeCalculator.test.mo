import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import SystemStakeCalculator "../../../../multi_backend/competition/staking/SystemStakeCalculator";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import TokenUtils "../../../../multi_backend/financial/TokenUtils";

// Helper function for absolute difference between Nats
func natAbsDiff(a : Nat, b : Nat) : Nat {
  if (a > b) { a - b } else { b - a };
};

// Mock token principals for testing
let govToken : Types.Token = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let multiToken : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let testToken1 : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
let testToken2 : Types.Token = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
let testToken3 : Types.Token = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

// Define constants for common percentage values using the same SCALING_FACTOR as in RatioOperations
let SCALING_FACTOR : Nat = 1_000_000_000;
let POINT_ONE_PERCENT : Nat = 1_000_000; // 0.1%
let ONE_PERCENT : Nat = 10_000_000; // 1%
let FIVE_PERCENT : Nat = 50_000_000; // 5%
let TEN_PERCENT : Nat = 100_000_000; // 10%
let TWENTY_PERCENT : Nat = 200_000_000; // 20%
let FIFTY_PERCENT : Nat = 500_000_000; // 50%
let ONE_HUNDRED_PERCENT : Nat = 1_000_000_000; // 100%

// Test suite for SystemStakeCalculator
suite(
  "Extended SystemStakeCalculator Tests",
  func() {
    // Test calculateSystemStake with different multiplier values
    test(
      "calculateSystemStake - with small multiplier",
      func() {
        // Setup test data with small multiplier value
        let totalPlayerStake : Nat = 1000;
        let multiplier : Types.Ratio = { value = POINT_ONE_PERCENT }; // 0.1%
        let baseRate : Types.Ratio = { value = FIVE_PERCENT }; // 5%
        let volumeLimit : Nat = 10000;
        let tokenType = govToken;

        // Execute the calculation
        let systemStake = SystemStakeCalculator.calculateSystemStake(
          totalPlayerStake,
          multiplier,
          baseRate,
          volumeLimit,
          tokenType,
        );

        // Verify:
        // maxStakeAtBaseRate = volumeLimit * baseRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalPlayerStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * multiplier = 500 * 0.001 = 0.5 (rounds to 0)

        assert systemStake.token == tokenType;
        assert systemStake.value == 0; // Should be 0 due to rounding
      },
    );

    test(
      "calculateSystemStake - with large multiplier",
      func() {
        // Setup test data with large multiplier
        let totalPlayerStake : Nat = 1000;
        let multiplier : Types.Ratio = { value = FIFTY_PERCENT }; // 50%
        let baseRate : Types.Ratio = { value = FIVE_PERCENT }; // 5%
        let volumeLimit : Nat = 10000;
        let tokenType = govToken;

        // Execute the calculation
        let systemStake = SystemStakeCalculator.calculateSystemStake(
          totalPlayerStake,
          multiplier,
          baseRate,
          volumeLimit,
          tokenType,
        );

        // Verify:
        // maxStakeAtBaseRate = volumeLimit * baseRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalPlayerStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * multiplier = 500 * 0.5 = 250

        assert systemStake.token == tokenType;
        assert systemStake.value == 250;
      },
    );

    test(
      "calculateSystemStake - with 100% multiplier",
      func() {
        // Setup test data with 100% multiplier (1.0)
        let totalPlayerStake : Nat = 1000;
        let multiplier : Types.Ratio = { value = ONE_HUNDRED_PERCENT }; // 100%
        let baseRate : Types.Ratio = { value = FIVE_PERCENT }; // 5%
        let volumeLimit : Nat = 10000;
        let tokenType = govToken;

        // Execute the calculation
        let systemStake = SystemStakeCalculator.calculateSystemStake(
          totalPlayerStake,
          multiplier,
          baseRate,
          volumeLimit,
          tokenType,
        );

        // Verify:
        // maxStakeAtBaseRate = volumeLimit * baseRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalPlayerStake, maxStakeAtBaseRate) = min(1000, 500) = 500
        // systemStake = effectiveStake * multiplier = 500 * 1.0 = 500

        assert systemStake.token == tokenType;
        assert systemStake.value == 500;
      },
    );

    // Test calculatePhantomPositions with different backing distributions
    test(
      "calculatePhantomPositions - with equal backing distribution",
      func() {
        // Setup test data with equal backing units
        let systemStake : Types.Amount = { token = multiToken; value = 100 };
        let stakeRate : Types.Ratio = { value = ONE_PERCENT }; // 1%
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = testToken1; backingUnit = 10 },
          { token = testToken2; backingUnit = 10 },
          { token = testToken3; backingUnit = 10 },
        ];

        // Execute the calculation
        let phantomPositions = SystemStakeCalculator.calculatePhantomPositions(
          systemStake,
          stakeRate,
          backingPairs,
        );

        // Verify: With equal backing units, each token should get 1/3 of the phantom positions
        // inversedStakeRate = 1 / 0.01 = 100
        // For each token:
        // tokenProportion = 10 / 30 = 1/3
        // tokenStake = systemStake * tokenProportion = 100 * 1/3 = 33.33 (rounds to 33)
        // phantomQuantity = tokenStake * inversedStakeRate = 33 * 100 = 3300

        assert phantomPositions.size() == 3;

        let (token1, amount1) = phantomPositions[0];
        let (token2, amount2) = phantomPositions[1];
        let (token3, amount3) = phantomPositions[2];

        assert token1 == testToken1;
        assert token2 == testToken2;
        assert token3 == testToken3;

        // Due to rounding in integer division, each value should be approximately 3300
        // But we allow small variations
        assert amount1.token == testToken1;
        assert amount2.token == testToken2;
        assert amount3.token == testToken3;

        // Check they're all approximately equal (within 1 unit of each other)
        assert natAbsDiff(amount1.value, amount2.value) <= 1;
        assert natAbsDiff(amount2.value, amount3.value) <= 1;
        assert natAbsDiff(amount1.value, amount3.value) <= 1;
      },
    );

    test(
      "calculatePhantomPositions - with very skewed backing distribution",
      func() {
        // Setup test data with highly skewed backing units
        let systemStake : Types.Amount = { token = multiToken; value = 1000 };
        let stakeRate : Types.Ratio = { value = TEN_PERCENT }; // 10%
        let backingPairs : [BackingTypes.BackingPair] = [
          { token = testToken1; backingUnit = 80 }, // 80% of backing
          { token = testToken2; backingUnit = 15 }, // 15% of backing
          { token = testToken3; backingUnit = 5 }, // 5% of backing
        ];

        // Execute the calculation
        let phantomPositions = SystemStakeCalculator.calculatePhantomPositions(
          systemStake,
          stakeRate,
          backingPairs,
        );

        // Verify: The phantom positions should be proportional to backing units
        // inversedStakeRate = 1 / 0.1 = 10
        // Total backing units = 80 + 15 + 5 = 100

        // For token1:
        // tokenProportion = 80 / 100 = 0.8
        // tokenStake = systemStake * tokenProportion = 1000 * 0.8 = 800
        // phantomQuantity = tokenStake * inversedStakeRate = 800 * 10 = 8000

        // For token2:
        // tokenProportion = 15 / 100 = 0.15
        // tokenStake = systemStake * tokenProportion = 1000 * 0.15 = 150
        // phantomQuantity = tokenStake * inversedStakeRate = 150 * 10 = 1500

        // For token3:
        // tokenProportion = 5 / 100 = 0.05
        // tokenStake = systemStake * tokenProportion = 1000 * 0.05 = 50
        // phantomQuantity = tokenStake * inversedStakeRate = 50 * 10 = 500

        assert phantomPositions.size() == 3;

        let (token1, amount1) = phantomPositions[0];
        let (token2, amount2) = phantomPositions[1];
        let (token3, amount3) = phantomPositions[2];

        assert token1 == testToken1;
        assert token2 == testToken2;
        assert token3 == testToken3;

        assert amount1.token == testToken1;
        assert amount2.token == testToken2;
        assert amount3.token == testToken3;

        // The values should be proportional to the backing units
        // Check if ratios are preserved (with small error margin for integer division)
        let ratio_1_to_2 = amount1.value / amount2.value;
        let backing_ratio_1_to_2 = 80 / 15; // approximately 5.33, but integer division gives 5

        let ratio_1_to_3 = amount1.value / amount3.value;
        let backing_ratio_1_to_3 = 80 / 5; // exactly 16

        let ratio_2_to_3 = amount2.value / amount3.value;
        let backing_ratio_2_to_3 = 15 / 5; // exactly 3

        // Since integer division truncates, we allow a small margin of error
        assert ratio_1_to_2 >= backing_ratio_1_to_2 - 1 and ratio_1_to_2 <= backing_ratio_1_to_2 + 1;
        assert ratio_1_to_3 >= backing_ratio_1_to_3 - 1 and ratio_1_to_3 <= backing_ratio_1_to_3 + 1;
        assert ratio_2_to_3 >= backing_ratio_2_to_3 - 1 and ratio_2_to_3 <= backing_ratio_2_to_3 + 1;
      },
    );

    test(
      "calculateSystemStake and calculatePhantomPositions - integration test",
      func() {
        // Setup combined test data for both functions
        let totalPlayerStake : Nat = 2000;
        let multiplier : Types.Ratio = { value = TWENTY_PERCENT }; // 20%
        let baseRate : Types.Ratio = { value = FIVE_PERCENT }; // 5%
        let volumeLimit : Nat = 10000;
        let tokenType = multiToken;

        let backingPairs : [BackingTypes.BackingPair] = [
          { token = testToken1; backingUnit = 50 },
          { token = testToken2; backingUnit = 30 },
          { token = testToken3; backingUnit = 20 },
        ];

        // First calculate the system stake
        let systemStake = SystemStakeCalculator.calculateSystemStake(
          totalPlayerStake,
          multiplier,
          baseRate,
          volumeLimit,
          tokenType,
        );

        // Then use that system stake to calculate phantom positions
        let phantomPositions = SystemStakeCalculator.calculatePhantomPositions(
          systemStake,
          baseRate,
          backingPairs,
        );

        // Verify systemStake:
        // maxStakeAtBaseRate = volumeLimit * baseRate = 10000 * 0.05 = 500
        // effectiveStake = min(totalPlayerStake, maxStakeAtBaseRate) = min(2000, 500) = 500
        // systemStake = effectiveStake * multiplier = 500 * 0.2 = 100

        assert systemStake.token == tokenType;
        assert systemStake.value == 100;

        // Verify phantomPositions:
        // inversedStakeRate = 1 / 0.05 = 20
        // Total backing units = 50 + 30 + 20 = 100

        // For token1:
        // tokenProportion = 50 / 100 = 0.5
        // tokenStake = systemStake * tokenProportion = 100 * 0.5 = 50
        // phantomQuantity = tokenStake * inversedStakeRate = 50 * 20 = 1000

        // For token2:
        // tokenProportion = 30 / 100 = 0.3
        // tokenStake = systemStake * tokenProportion = 100 * 0.3 = 30
        // phantomQuantity = tokenStake * inversedStakeRate = 30 * 20 = 600

        // For token3:
        // tokenProportion = 20 / 100 = 0.2
        // tokenStake = systemStake * tokenProportion = 100 * 0.2 = 20
        // phantomQuantity = tokenStake * inversedStakeRate = 20 * 20 = 400

        assert phantomPositions.size() == 3;

        let (token1, amount1) = phantomPositions[0];
        let (token2, amount2) = phantomPositions[1];
        let (token3, amount3) = phantomPositions[2];

        // Check tokens match
        assert token1 == testToken1;
        assert token2 == testToken2;
        assert token3 == testToken3;

        // Check the phantom amounts (within 1% tolerance for rounding errors)
        let tolerance = func(expected : Nat, actual : Nat) : Bool {
          if (expected == 0 and actual == 0) return true;
          let diff = if (expected > actual) expected - actual else actual - expected;
          let percentage = (diff * 100) / expected;
          return percentage <= 1; // Allow 1% tolerance
        };

        assert tolerance(1000, amount1.value);
        assert tolerance(600, amount2.value);
        assert tolerance(400, amount3.value);
      },
    );

    test(
      "calculateSystemStake - extreme case with zero player stake",
      func() {
        // Setup with zero player stake
        let totalPlayerStake : Nat = 0;
        let multiplier : Types.Ratio = { value = TWENTY_PERCENT }; // 20%
        let baseRate : Types.Ratio = { value = FIVE_PERCENT }; // 5%
        let volumeLimit : Nat = 10000;
        let tokenType = govToken;

        // Execute the calculation
        let systemStake = SystemStakeCalculator.calculateSystemStake(
          totalPlayerStake,
          multiplier,
          baseRate,
          volumeLimit,
          tokenType,
        );

        // Verify: with zero player stake, result should be zero
        assert systemStake.token == tokenType;
        assert systemStake.value == 0;
      },
    );
  },
);
