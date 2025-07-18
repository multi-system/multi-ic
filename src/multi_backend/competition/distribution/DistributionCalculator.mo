import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import EventTypes "../../types/EventTypes";
import RatioOperations "../../financial/RatioOperations";
import AmountOperations "../../financial/AmountOperations";
import PriceOperations "../../financial/PriceOperations";

/**
 * DistributionCalculator provides pure calculation functions for the distribution phase.
 * No side effects - just mathematical computations based on the whitepaper formulas.
 * Token-agnostic design - all functions work with single token types.
 */
module {
  // Result of performance calculation for a single position
  public type PositionPerformance = {
    position : RewardTypes.Position;
    value : Nat; // Current value in Multi tokens
    relativePerformance : Types.Ratio; // omega_i,t from whitepaper
  };

  /**
   * Calculate how much of a stake should be distributed in a specific distribution event.
   *
   * Mathematical distribution to ensure no remainders:
   * - 100/3: distributions get [33, 33, 34]
   * - 101/3: distributions get [33, 34, 34]
   * - 102/3: distributions get [34, 34, 34]
   *
   * The last 'remainder' distributions get +1 token each.
   *
   * @param stake The total stake amount
   * @param distributionNumber The current distribution number (0-based)
   * @param totalDistributions Total number of distributions
   * @returns The exact amount for this distribution
   */
  public func calculateDistributionStake(
    stake : Types.Amount,
    distributionNumber : Nat,
    totalDistributions : Nat,
  ) : Types.Amount {
    if (totalDistributions == 0) {
      Debug.trap("Invalid totalDistributions: cannot be zero");
    };

    // Calculate base amount and remainder
    let baseAmount = stake.value / totalDistributions;
    let remainder = stake.value % totalDistributions;

    // The last 'remainder' distributions get the extra token
    let firstDistributionWithExtra = totalDistributions - remainder;

    let amountForThisDistribution = if (distributionNumber >= firstDistributionWithExtra) {
      baseAmount + 1;
    } else {
      baseAmount;
    };

    AmountOperations.new(stake.token, amountForThisDistribution);
  };

  /**
   * Calculate the total pool for a distribution from all position stakes.
   *
   * @param stakes Array of stake amounts from all positions
   * @param distributionNumber Current distribution number
   * @param totalDistributions Total number of distributions
   * @returns Total pool amount
   */
  public func calculateDistributionPool(
    stakes : [Types.Amount],
    distributionNumber : Nat,
    totalDistributions : Nat,
  ) : Types.Amount {
    if (stakes.size() == 0) {
      Debug.trap("Cannot calculate pool from empty stakes array");
    };

    // Calculate each position's contribution for this distribution
    let contributions = Array.map<Types.Amount, Types.Amount>(
      stakes,
      func(stake) {
        calculateDistributionStake(stake, distributionNumber, totalDistributions);
      },
    );

    // Sum all contributions using AmountOperations
    AmountOperations.sum(contributions);
  };

  /**
   * Calculate the current value of a position at distribution time.
   * Formula: v_i,t = P_i,t * q_i
   *
   * @param position The position to value
   * @param price The current price for the position's token
   * @returns Value in Multi tokens
   */
  public func calculatePositionValue(
    position : RewardTypes.Position,
    price : Types.Price,
  ) : Nat {
    // Verify price is for the correct token
    if (not (position.quantity.token == price.baseToken)) {
      Debug.trap("Price token mismatch in calculatePositionValue");
    };

    // Calculate value using PriceOperations
    let valueAmount = PriceOperations.calculateValue(position.quantity, price);
    valueAmount.value;
  };

  /**
   * Calculate relative performance for all positions.
   * Formula: omega_i,t = v_i,t / Sum(v_j,t)
   *
   * @param positions All positions in the competition
   * @param priceEvent Price event containing current prices
   * @returns Array of position performances
   */
  public func calculatePerformances(
    positions : [RewardTypes.Position],
    priceEvent : EventTypes.PriceEvent,
  ) : [PositionPerformance] {
    if (positions.size() == 0) {
      return [];
    };

    // Calculate values for all positions
    let positionValues = Array.map<RewardTypes.Position, (RewardTypes.Position, Nat)>(
      positions,
      func(position) {
        // Find price for this position's token
        let priceOpt = Array.find<Types.Price>(
          priceEvent.prices,
          func(p) { p.baseToken == position.quantity.token },
        );

        switch (priceOpt) {
          case (null) {
            Debug.trap("No price found for token in position");
          };
          case (?price) {
            let value = calculatePositionValue(position, price);
            (position, value);
          };
        };
      },
    );

    // Calculate total value
    let totalValue = Array.foldLeft<(RewardTypes.Position, Nat), Nat>(
      positionValues,
      0,
      func(acc, (_, value)) { acc + value },
    );

    // Handle edge case where all positions have zero value
    if (totalValue == 0) {
      return Array.map<(RewardTypes.Position, Nat), PositionPerformance>(
        positionValues,
        func((position, value)) {
          {
            position = position;
            value = value;
            relativePerformance = RatioOperations.fromDecimal(0);
          };
        },
      );
    };

    // Calculate relative performances using RatioOperations
    Array.map<(RewardTypes.Position, Nat), PositionPerformance>(
      positionValues,
      func((position, value)) {
        {
          position = position;
          value = value;
          relativePerformance = RatioOperations.fromNats(value, totalValue);
        };
      },
    );
  };

  /**
   * Calculate reward for a single position based on its performance and the pool.
   * Token-agnostic - works with any single token type.
   *
   * @param performance The position's relative performance
   * @param pool The total pool to distribute
   * @returns Reward amount
   */
  public func calculatePositionReward(
    performance : Types.Ratio,
    pool : Types.Amount,
  ) : Types.Amount {
    RatioOperations.applyToAmount(pool, performance);
  };

  /**
   * Calculate rewards for all positions from a pool.
   *
   * @param performances Array of position performances
   * @param pool Total pool to distribute
   * @returns Array of rewards
   */
  public func calculateRewards(
    performances : [PositionPerformance],
    pool : Types.Amount,
  ) : [Types.Amount] {
    Array.map<PositionPerformance, Types.Amount>(
      performances,
      func(perf) {
        calculatePositionReward(perf.relativePerformance, pool);
      },
    );
  };

  /**
   * Calculate final rewards including remainder distribution.
   * Remainders from rounding are distributed round-robin starting from position 0.
   *
   * @param performances Position performances
   * @param pool Total pool amount
   * @returns Final rewards for each position
   */
  public func calculateFinalRewards(
    performances : [PositionPerformance],
    pool : Types.Amount,
  ) : [Types.Amount] {
    if (performances.size() == 0) {
      return [];
    };

    // Calculate base rewards
    let baseRewards = calculateRewards(performances, pool);

    // Calculate total distributed
    let totalDistributed = if (baseRewards.size() > 0) {
      AmountOperations.sum(baseRewards);
    } else {
      AmountOperations.new(pool.token, 0);
    };

    // Calculate remainder from rounding
    let remainder = if (AmountOperations.canSubtract(pool, totalDistributed)) {
      AmountOperations.subtract(pool, totalDistributed);
    } else {
      AmountOperations.new(pool.token, 0);
    };

    // If no remainder, return base rewards
    if (AmountOperations.isZero(remainder)) {
      return baseRewards;
    };

    // Distribute remainder tokens round-robin
    let finalRewards = Array.thaw<Types.Amount>(baseRewards);
    var remainingTokens = remainder.value;
    var index = 0;

    while (remainingTokens > 0 and finalRewards.size() > 0) {
      finalRewards[index] := AmountOperations.add(
        finalRewards[index],
        AmountOperations.new(remainder.token, 1),
      );
      remainingTokens -= 1;
      index := (index + 1) % finalRewards.size();
    };

    Array.freeze(finalRewards);
  };
};
