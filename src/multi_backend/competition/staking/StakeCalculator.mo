import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Types "../../types/Types";
import BackingTypes "../../types/BackingTypes";
import RatioOperations "../../financial/RatioOperations";
import AmountOperations "../../financial/AmountOperations";
import PriceOperations "../../financial/PriceOperations";
import TokenUtils "../../financial/TokenUtils";

module {
  /**
   * Calculates the equivalent stake amount in a different token type.
   * Works with any two stake tokens in the system.
   *
   * Formula: stake1 / rate1 = stake2 / rate2
   * Therefore: stake2 = stake1 * (rate2 / rate1)
   *
   * @param knownStake The known stake amount in any stake token
   * @param knownRate The stake rate for the known stake's token
   * @param targetRate The stake rate for the target token
   * @param targetToken The token for which to calculate the equivalent stake
   * @returns The equivalent stake amount in the target token
   */
  public func calculateEquivalentStake(
    knownStake : Types.Amount,
    knownRate : Types.Ratio,
    targetRate : Types.Ratio,
    targetToken : Types.Token,
  ) : Types.Amount {
    // Calculate the ratio between the target rate and known rate
    let rateRatio = RatioOperations.divide(targetRate, knownRate);

    // Apply this ratio to the known stake amount
    let equivalentAmount = RatioOperations.applyToAmount(knownStake, rateRatio);

    // Return with the correct target token
    { token = targetToken; value = equivalentAmount.value };
  };

  /**
   * Calculates the adjusted stake rate for any stake token.
   * Formula: adjusted_rate = max(current_rate, total_stake / volume_limit)
   *
   * @param currentRate The current stake rate for this token
   * @param totalStake The sum of all player stakes for this token
   * @param volumeLimit The calculated volume limit (theta * M_start)
   * @returns The adjusted stake rate
   */
  public func calculateAdjustedStakeRate(
    currentRate : Types.Ratio,
    totalStake : Nat,
    volumeLimit : Nat,
  ) : Types.Ratio {
    if (volumeLimit == 0) {
      Debug.trap("Volume limit cannot be zero in calculateAdjustedStakeRate");
    };

    // Create a ratio from totalStake/volumeLimit
    let calculatedRate = RatioOperations.fromNats(totalStake, volumeLimit);

    // Return the maximum of current rate and calculated rate
    RatioOperations.max(currentRate, calculatedRate);
  };

  /**
   * Calculates the token quantity based on stake amount and rate.
   * According to the whitepaper formula: q_i = s_i / (r_sigma * P_comp_k)
   *
   * This formula works with any stake token type sigma (Foresight or Multi),
   * as long as the corresponding rate r_sigma is used.
   *
   * @param stake The stake amount in any stake token type
   * @param adjustedStakeRate The adjusted stake rate for the stake token
   * @param competitionPrice The competition price for the proposed token
   * @returns The token quantity that can be represented by this stake
   */
  public func calculateTokenQuantity(
    stake : Types.Amount,
    adjustedStakeRate : Types.Ratio,
    competitionPrice : Types.Price,
  ) : Types.Amount {
    // No validation needed - the whitepaper formula works with any stake token type
    // as long as the correct rate is used for that token

    // Calculate denominator: rate * price
    let denominator = RatioOperations.multiply(adjustedStakeRate, competitionPrice.value);

    if (denominator.value == 0) {
      Debug.trap("Denominator in calculateTokenQuantity is zero");
    };

    // Calculate token quantity: stake / (rate * price)
    let inverseMultiplier = RatioOperations.inverse(denominator);
    let tokenQuantity = RatioOperations.applyToAmount(stake, inverseMultiplier);

    // Return with the base token from the price
    { token = competitionPrice.baseToken; value = tokenQuantity.value };
  };

  /**
   * Calculates the system stake amount for any stake token.
   * Formula: S = lambda * min(total_player_stake, theta * M_start * r)
   *
   * @param totalPlayerStake The sum of all player stakes for this token
   * @param multiplier The system stake multiplier (lambda) for this token
   * @param baseRate The base stake rate (r) for this token
   * @param volumeLimit The calculated volume limit (theta * M_start)
   * @param tokenType The stake token type
   * @returns The system stake amount for this token
   */
  public func calculateSystemStake(
    totalPlayerStake : Nat,
    multiplier : Types.Ratio,
    baseRate : Types.Ratio,
    volumeLimit : Nat,
    tokenType : Types.Token,
  ) : Types.Amount {
    let maxStakeAtBaseRate = RatioOperations.applyToAmount(
      { token = tokenType; value = volumeLimit },
      baseRate,
    ).value;

    let effectiveStake = Nat.min(totalPlayerStake, maxStakeAtBaseRate);

    let effectiveStakeAmount = { token = tokenType; value = effectiveStake };
    let systemStakeAmount = RatioOperations.applyToAmount(effectiveStakeAmount, multiplier);

    { token = tokenType; value = systemStakeAmount.value };
  };

  /**
   * Calculates phantom positions for backing tokens based on system stake.
   * Phantom positions represent hypothetical trades: q_k = s_k / r
   *
   * @param systemStake The total system stake (typically multi token)
   * @param stakeRate The current stake rate for the token
   * @param backingPairs The current backing pairs representing token distribution
   * @returns Array of phantom positions for each backing token
   */
  public func calculatePhantomPositions(
    systemStake : Types.Amount,
    stakeRate : Types.Ratio,
    backingPairs : [BackingTypes.BackingPair],
  ) : [(Types.Token, Types.Amount)] {
    let totalBackingUnits = Array.foldLeft<BackingTypes.BackingPair, Nat>(
      backingPairs,
      0,
      func(acc, pair) { acc + pair.backingUnit },
    );

    if (totalBackingUnits == 0) {
      return [];
    };

    Array.map<BackingTypes.BackingPair, (Types.Token, Types.Amount)>(
      backingPairs,
      func(pair) {
        let proportion = RatioOperations.fromNats(pair.backingUnit, totalBackingUnits);
        let tokenStake = RatioOperations.applyToAmount(systemStake, proportion);
        let phantomQuantity = RatioOperations.applyToAmount(
          tokenStake,
          RatioOperations.inverse(stakeRate),
        );

        (pair.token, { token = pair.token; value = phantomQuantity.value });
      },
    );
  };
};
