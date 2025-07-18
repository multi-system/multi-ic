import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import RewardTypes "../../../../multi_backend/types/RewardTypes";
import EventTypes "../../../../multi_backend/types/EventTypes";
import DistributionCalculator "../../../../multi_backend/competition/distribution/DistributionCalculator";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import AmountOperations "../../../../multi_backend/financial/AmountOperations";
import CompetitionTestUtils "../CompetitionTestUtils";

// Mock token principals for testing
let govToken : Types.Token = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let multiToken : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let tokenA : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
let tokenB : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let tokenC : Types.Token = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

// Define constants for common percentage values
let SCALING_FACTOR : Nat = 1_000_000_000;
let ONE_PERCENT : Nat = 10_000_000; // 1%
let FIVE_PERCENT : Nat = 50_000_000; // 5%
let TEN_PERCENT : Nat = 100_000_000; // 10%
let TWENTY_PERCENT : Nat = 200_000_000; // 20%
let TWENTY_FIVE_PERCENT : Nat = 250_000_000; // 25%
let THIRTY_PERCENT : Nat = 300_000_000; // 30%
let FIFTY_PERCENT : Nat = 500_000_000; // 50%
let ONE_HUNDRED_PERCENT : Nat = 1_000_000_000; // 100%
let TWO_HUNDRED_PERCENT : Nat = 2_000_000_000; // 200%

// Helper function to create a test price
func createPrice(baseToken : Types.Token, value : Nat) : Types.Price {
  {
    baseToken = baseToken;
    quoteToken = multiToken;
    value = { value = value };
  };
};

// Test suite for DistributionCalculator
suite(
  "DistributionCalculator Tests",
  func() {

    // Test calculateDistributionStake
    test(
      "calculateDistributionStake - 100 tokens over 3 distributions",
      func() {
        let stake = AmountOperations.new(govToken, 100);

        // Distribution 0: should get 33
        let dist0 = DistributionCalculator.calculateDistributionStake(stake, 0, 3);
        assert dist0.value == 33;

        // Distribution 1: should get 33
        let dist1 = DistributionCalculator.calculateDistributionStake(stake, 1, 3);
        assert dist1.value == 33;

        // Distribution 2: should get 34 (gets the remainder)
        let dist2 = DistributionCalculator.calculateDistributionStake(stake, 2, 3);
        assert dist2.value == 34;

        // Total should equal original stake
        assert dist0.value + dist1.value + dist2.value == 100;
      },
    );

    test(
      "calculateDistributionStake - 101 tokens over 3 distributions",
      func() {
        let stake = AmountOperations.new(govToken, 101);

        // Distribution 0: should get 33
        let dist0 = DistributionCalculator.calculateDistributionStake(stake, 0, 3);
        assert dist0.value == 33;

        // Distribution 1: should get 34
        let dist1 = DistributionCalculator.calculateDistributionStake(stake, 1, 3);
        assert dist1.value == 34;

        // Distribution 2: should get 34
        let dist2 = DistributionCalculator.calculateDistributionStake(stake, 2, 3);
        assert dist2.value == 34;

        // Total should equal original stake
        assert dist0.value + dist1.value + dist2.value == 101;
      },
    );

    test(
      "calculateDistributionStake - 102 tokens over 3 distributions",
      func() {
        let stake = AmountOperations.new(govToken, 102);

        // All distributions should get 34 (divides evenly)
        let dist0 = DistributionCalculator.calculateDistributionStake(stake, 0, 3);
        assert dist0.value == 34;

        let dist1 = DistributionCalculator.calculateDistributionStake(stake, 1, 3);
        assert dist1.value == 34;

        let dist2 = DistributionCalculator.calculateDistributionStake(stake, 2, 3);
        assert dist2.value == 34;

        // Total should equal original stake
        assert dist0.value + dist1.value + dist2.value == 102;
      },
    );

    // Test calculateDistributionPool
    test(
      "calculateDistributionPool - single token type",
      func() {
        let stakes = [
          AmountOperations.new(govToken, 100),
          AmountOperations.new(govToken, 200),
          AmountOperations.new(govToken, 300),
        ];

        let pool = DistributionCalculator.calculateDistributionPool(stakes, 0, 10);

        // Each stake contributes 1/10th
        assert pool.value == 60; // (100 + 200 + 300) / 10
      },
    );

    test(
      "calculateDistributionPool - last distribution gets remainders",
      func() {
        let stakes = [
          AmountOperations.new(multiToken, 101),
          AmountOperations.new(multiToken, 102),
        ];

        // First distribution
        let pool0 = DistributionCalculator.calculateDistributionPool(stakes, 0, 3);
        assert pool0.value == 67; // 33 + 34

        // Last distribution includes remainders
        let pool2 = DistributionCalculator.calculateDistributionPool(stakes, 2, 3);
        assert pool2.value == 68; // 34 + 34
      },
    );

    // Test calculatePositionValue
    test(
      "calculatePositionValue - basic calculation",
      func() {
        let position = CompetitionTestUtils.createTestPosition(tokenA, 1000, 100, 200, ?1, false);
        let price = createPrice(tokenA, FIFTY_PERCENT); // 0.5

        let value = DistributionCalculator.calculatePositionValue(position, price);

        // Expected: 1000 * 0.5 = 500
        assert value == 500;
      },
    );

    test(
      "calculatePositionValue - with high price",
      func() {
        let position = CompetitionTestUtils.createTestPosition(tokenB, 500, 50, 100, ?1, false);
        let price = createPrice(tokenB, TWO_HUNDRED_PERCENT); // 2.0

        let value = DistributionCalculator.calculatePositionValue(position, price);

        // Expected: 500 * 2.0 = 1000
        assert value == 1000;
      },
    );

    // Test calculatePerformances
    test(
      "calculatePerformances - equal values",
      func() {
        let positions = [
          CompetitionTestUtils.createTestPosition(tokenA, 1000, 100, 200, ?1, false),
          CompetitionTestUtils.createTestPosition(tokenB, 500, 100, 200, ?2, false),
          CompetitionTestUtils.createTestPosition(tokenC, 2000, 100, 200, null, true), // System position
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            createPrice(tokenA, ONE_HUNDRED_PERCENT), // 1.0
            createPrice(tokenB, TWO_HUNDRED_PERCENT), // 2.0
            createPrice(tokenC, FIFTY_PERCENT), // 0.5
          ];
        };

        let performances = DistributionCalculator.calculatePerformances(positions, priceEvent);

        // Values: A=1000, B=1000, C=1000, Total=3000
        // Each should have 33.33% performance
        assert performances.size() == 3;

        for (perf in performances.vals()) {
          assert perf.value == 1000;
          // Check relative performance is approximately 1/3
          let oneThird = RatioOperations.fromNats(1, 3);
          let tolerance = { value = 1_000_000 }; // 0.1% tolerance
          assert RatioOperations.withinTolerance(perf.relativePerformance, oneThird, tolerance);
        };
      },
    );

    test(
      "calculatePerformances - different values",
      func() {
        let positions = [
          CompetitionTestUtils.createTestPosition(tokenA, 1000, 100, 200, ?1, false),
          CompetitionTestUtils.createTestPosition(tokenB, 2000, 150, 300, ?2, false),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            createPrice(tokenA, TWENTY_PERCENT), // 0.2
            createPrice(tokenB, TEN_PERCENT), // 0.1
          ];
        };

        let performances = DistributionCalculator.calculatePerformances(positions, priceEvent);

        // Values: A=200, B=200, Total=400
        // Each should have 50% performance
        assert performances.size() == 2;
        assert performances[0].value == 200;
        assert performances[1].value == 200;

        let halfRatio = RatioOperations.fromNats(1, 2);
        assert performances[0].relativePerformance.value == halfRatio.value;
        assert performances[1].relativePerformance.value == halfRatio.value;
      },
    );

    // Test calculatePositionReward (token-agnostic)
    test(
      "calculatePositionReward - applies performance ratio",
      func() {
        let pool = AmountOperations.new(govToken, 10000);
        let performance = { value = TWENTY_PERCENT }; // 20%

        let reward = DistributionCalculator.calculatePositionReward(performance, pool);

        assert reward.value == 2000; // 20% of 10000
        assert reward.token == govToken;
      },
    );

    // Test calculateRewards
    test(
      "calculateRewards - distributes pool based on performances",
      func() {
        let performances = [
          {
            position = CompetitionTestUtils.createTestPosition(tokenA, 1000, 100, 200, ?1, false);
            value = 1000;
            relativePerformance = { value = FIFTY_PERCENT }; // 50%
          },
          {
            position = CompetitionTestUtils.createTestPosition(tokenB, 500, 100, 200, ?2, false);
            value = 500;
            relativePerformance = { value = THIRTY_PERCENT }; // 30%
          },
          {
            position = CompetitionTestUtils.createTestPosition(tokenC, 200, 100, 200, ?3, false);
            value = 200;
            relativePerformance = { value = TWENTY_PERCENT }; // 20%
          },
        ];

        let pool = AmountOperations.new(multiToken, 10000);
        let rewards = DistributionCalculator.calculateRewards(performances, pool);

        assert rewards.size() == 3;
        assert rewards[0].value == 5000; // 50% of 10000
        assert rewards[1].value == 3000; // 30% of 10000
        assert rewards[2].value == 2000; // 20% of 10000

        // Verify total distributed equals pool
        let totalDistributed = AmountOperations.sum(rewards);
        assert totalDistributed.value == 10000;
      },
    );

    // Test calculateFinalRewards with remainder
    test(
      "calculateFinalRewards - handles rounding remainder",
      func() {
        let performances = [
          {
            position = CompetitionTestUtils.createTestPosition(tokenA, 1000, 100, 200, ?1, false);
            value = 1000;
            relativePerformance = { value = 333_333_333 }; // ~33.33%
          },
          {
            position = CompetitionTestUtils.createTestPosition(tokenB, 1000, 100, 200, ?2, false);
            value = 1000;
            relativePerformance = { value = 333_333_333 }; // ~33.33%
          },
          {
            position = CompetitionTestUtils.createTestPosition(tokenC, 1000, 100, 200, ?3, false);
            value = 1000;
            relativePerformance = { value = 333_333_334 }; // ~33.33%
          },
        ];

        let pool = AmountOperations.new(govToken, 100);
        let finalRewards = DistributionCalculator.calculateFinalRewards(performances, pool);

        // Each should get approximately 33, with remainder distributed round-robin
        assert finalRewards.size() == 3;
        let total = finalRewards[0].value + finalRewards[1].value + finalRewards[2].value;
        assert total == 100; // All tokens distributed

        // With round-robin distribution of remainder
        assert finalRewards[0].value == 34; // 33 + 1 remainder
        assert finalRewards[1].value == 33;
        assert finalRewards[2].value == 33;
      },
    );

    // Edge cases
    test(
      "calculatePerformances - empty positions",
      func() {
        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [];
        };

        let performances = DistributionCalculator.calculatePerformances([], priceEvent);
        assert performances.size() == 0;
      },
    );

    test(
      "calculatePerformances - all zero values",
      func() {
        let positions = [
          CompetitionTestUtils.createTestPosition(tokenA, 0, 100, 200, ?1, false),
          CompetitionTestUtils.createTestPosition(tokenB, 0, 100, 200, ?2, false),
        ];

        let priceEvent : EventTypes.PriceEvent = {
          id = 1;
          heartbeatId = 1;
          prices = [
            createPrice(tokenA, ONE_HUNDRED_PERCENT),
            createPrice(tokenB, ONE_HUNDRED_PERCENT),
          ];
        };

        let performances = DistributionCalculator.calculatePerformances(positions, priceEvent);

        // All values are zero, so relative performance should be zero
        for (perf in performances.vals()) {
          assert perf.value == 0;
          assert perf.relativePerformance.value == 0;
        };
      },
    );
  },
);
