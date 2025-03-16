import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import StakeCalculator "../../../../multi_backend/competition/staking/StakeCalculator";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import TokenUtils "../../../../multi_backend/financial/TokenUtils";

// Mock token principals for testing
let govToken : Types.Token = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let multiToken : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let testToken : Types.Token = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

// Define constants for common percentage values using the same SCALING_FACTOR as in RatioOperations
let SCALING_FACTOR : Nat = 1_000_000_000;
let POINT_ONE_PERCENT : Nat = 1_000_000; // 0.1%
let POINT_FIVE_PERCENT : Nat = 5_000_000; // 0.5%
let ONE_PERCENT : Nat = 10_000_000; // 1%
let FIVE_PERCENT : Nat = 50_000_000; // 5%
let TEN_PERCENT : Nat = 100_000_000; // 10%
let TWENTY_PERCENT : Nat = 200_000_000; // 20%
let FORTY_PERCENT : Nat = 400_000_000; // 40%
let FIFTY_PERCENT : Nat = 500_000_000; // 50%
let ONE_HUNDRED_PERCENT : Nat = 1_000_000_000; // 100%
let TWO_HUNDRED_PERCENT : Nat = 2_000_000_000; // 200% (2.0)

// Test suite for StakeCalculator
suite(
  "StakeCalculator Tests",
  func() {

    // Test calculateEquivalentStake
    test(
      "calculateEquivalentStake - convert gov to multi stake",
      func() {
        // Setup test data
        let govStake : Types.Amount = { token = govToken; value = 100 };
        let govRate : Types.Ratio = { value = FIVE_PERCENT };
        let multiRate : Types.Ratio = { value = POINT_FIVE_PERCENT * 4 }; // 2%

        // Execute the calculation
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          govRate,
          multiRate,
          multiToken,
        );

        // Verify results:
        // Expected: 100 * (2% / 5%) = 100 * 0.4 = 40
        assert multiStake.token == multiToken;
        assert multiStake.value == 40;
      },
    );

    test(
      "calculateEquivalentStake - with equal rates",
      func() {
        // Setup test data with equal rates
        let govStake : Types.Amount = { token = govToken; value = 100 };
        let govRate : Types.Ratio = { value = FIVE_PERCENT };
        let multiRate : Types.Ratio = { value = FIVE_PERCENT }; // Same 5%

        // Execute
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          govRate,
          multiRate,
          multiToken,
        );

        // Verify: should be the same amount (except for the token)
        assert multiStake.token == multiToken;
        assert multiStake.value == 100;
      },
    );

    test(
      "calculateEquivalentStake - with zero stake",
      func() {
        // Setup test data
        let govStake : Types.Amount = { token = govToken; value = 0 };
        let govRate : Types.Ratio = { value = FIVE_PERCENT };
        let multiRate : Types.Ratio = { value = POINT_FIVE_PERCENT * 4 }; // 2%

        // Execute
        let multiStake = StakeCalculator.calculateEquivalentStake(
          govStake,
          govRate,
          multiRate,
          multiToken,
        );

        // Verify: with zero stake, result should be zero
        assert multiStake.token == multiToken;
        assert multiStake.value == 0;
      },
    );

    // Test calculateAdjustedStakeRate
    test(
      "calculateAdjustedStakeRate - below volume limit",
      func() {
        // Setup test data
        let currentRate : Types.Ratio = { value = FIFTY_PERCENT };
        let totalStake : Nat = 400; // 40% of volume limit
        let volumeLimit : Nat = 1000;

        // Execute
        let adjustedRate = StakeCalculator.calculateAdjustedStakeRate(
          currentRate,
          totalStake,
          volumeLimit,
        );

        // Calculate expected: totalStake/volumeLimit = 400/1000 = 0.4 = 40%
        let calculatedRate = RatioOperations.fromNats(400, 1000);

        // Verify: when totalStake/volumeLimit (40%) < currentRate (50%),
        // the adjusted rate should remain at the current rate (50%)
        assert adjustedRate.value == currentRate.value;
        assert adjustedRate.value > calculatedRate.value;
      },
    );

    test(
      "calculateAdjustedStakeRate - above volume limit",
      func() {
        // Setup test data
        let currentRate : Types.Ratio = { value = FIVE_PERCENT };
        let totalStake : Nat = 800;
        let volumeLimit : Nat = 1000;

        // Execute
        let adjustedRate = StakeCalculator.calculateAdjustedStakeRate(
          currentRate,
          totalStake,
          volumeLimit,
        );

        // Calculate expected: totalStake/volumeLimit = 800/1000 = 0.8 = 80%
        let calculatedRate = RatioOperations.fromNats(800, 1000);

        // Verify: when totalStake/volumeLimit (80%) > currentRate (5%),
        // the adjusted rate should be the calculated rate (80%)
        assert adjustedRate.value == calculatedRate.value;
        assert adjustedRate.value > currentRate.value;
      },
    );

    test(
      "calculateAdjustedStakeRate - at volume limit",
      func() {
        // Setup: totalStake exactly at volumeLimit
        let currentRate : Types.Ratio = { value = FIVE_PERCENT };
        let totalStake : Nat = 1000;
        let volumeLimit : Nat = 1000;

        // Execute
        let adjustedRate = StakeCalculator.calculateAdjustedStakeRate(
          currentRate,
          totalStake,
          volumeLimit,
        );

        // Calculated rate: 1000/1000 = 1.0 = 100%
        let calculatedRate = RatioOperations.fromNats(1000, 1000);

        // Verify: should be the calculated rate (100%) since it's higher
        assert adjustedRate.value == calculatedRate.value;
        assert adjustedRate.value > currentRate.value;
      },
    );

    // Test calculateTokenQuantity
    test(
      "calculateTokenQuantity - basic test",
      func() {
        // Setup test data
        let stake : Types.Amount = { token = multiToken; value = 100 };
        let adjustedRate : Types.Ratio = { value = POINT_FIVE_PERCENT };
        let price : Types.Price = {
          baseToken = testToken;
          quoteToken = multiToken;
          value = { value = TWENTY_PERCENT }; // 0.2 (20%)
        };

        // Execute
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          stake,
          adjustedRate,
          price,
        );

        // Expected: stake / (rate * price) = 100 / (0.005 * 0.2) = 100 / 0.001 = 100,000
        assert tokenQuantity.token == testToken;
        assert tokenQuantity.value == 100_000;
      },
    );

    test(
      "calculateTokenQuantity - with small values",
      func() {
        // Setup test data with small values
        let stake : Types.Amount = { token = multiToken; value = 10 };
        let adjustedRate : Types.Ratio = { value = POINT_ONE_PERCENT };
        let price : Types.Price = {
          baseToken = testToken;
          quoteToken = multiToken;
          value = { value = FIVE_PERCENT }; // 0.05 (5%)
        };

        // Execute
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          stake,
          adjustedRate,
          price,
        );

        // Expected: 10 / (0.001 * 0.05) = 10 / 0.00005 = 200,000
        assert tokenQuantity.token == testToken;
        assert tokenQuantity.value == 200_000;
      },
    );

    test(
      "calculateTokenQuantity - with high rate",
      func() {
        // Setup test data with high rate
        let stake : Types.Amount = { token = multiToken; value = 1000 };
        let adjustedRate : Types.Ratio = { value = FIVE_PERCENT };
        let price : Types.Price = {
          baseToken = testToken;
          quoteToken = multiToken;
          value = { value = TEN_PERCENT }; // 0.1 (10%)
        };

        // Execute
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          stake,
          adjustedRate,
          price,
        );

        // Expected: 1000 / (0.05 * 0.1) = 1000 / 0.005 = 200,000
        assert tokenQuantity.token == testToken;
        assert tokenQuantity.value == 200_000;
      },
    );

    test(
      "calculateTokenQuantity - precision test",
      func() {
        // Setup test data with values that require precision
        let stake : Types.Amount = { token = multiToken; value = 123 };
        let adjustedRate : Types.Ratio = { value = 3_333_333 }; // approximately 3.33%
        let price : Types.Price = {
          baseToken = testToken;
          quoteToken = multiToken;
          value = { value = 123_456_789 }; // approximately 1.23
        };

        // Execute
        let tokenQuantity = StakeCalculator.calculateTokenQuantity(
          stake,
          adjustedRate,
          price,
        );

        // Here we calculate the expected value ourselves to compare
        // Expected: stake / (rate * price)
        let denominator = RatioOperations.multiply(adjustedRate, price.value);
        let inverseMultiplier = RatioOperations.inverse(denominator);
        let expected = RatioOperations.applyToAmount(stake, inverseMultiplier);

        // Verify the token and the expected value
        assert tokenQuantity.token == testToken;
        assert tokenQuantity.value == expected.value;
      },
    );
  },
);
