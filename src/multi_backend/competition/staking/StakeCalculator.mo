import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Types "../../types/Types";
import RatioOperations "../../financial/RatioOperations";
import AmountOperations "../../financial/AmountOperations";
import PriceOperations "../../financial/PriceOperations";
import TokenUtils "../../financial/TokenUtils";

// StakeCalculator provides core calculations for stake amounts, token quantities,
// and conversions between them according to the Foresight protocol specifications.
module {
  /**
   * Calculates the equivalent stake amount in a different token type.
   *
   * This function implements the stake consistency formula: stake1 / rate1 = stake2 / rate2
   * where:
   * - stake1 is the known stake amount in token1
   * - rate1 is the stake rate for token1
   * - rate2 is the stake rate for token2
   * - stake2 is the equivalent stake amount in token2 (what this function calculates)
   *
   * The function ensures that stakes in different tokens represent the same underlying value,
   * which is essential for the Foresight protocol's stake consistency model.
   *
   * @param {Types.Amount} knownStake - The known stake amount in token1
   * @param {Types.Ratio} knownRate - The stake rate for the known stake's token
   * @param {Types.Ratio} targetRate - The stake rate for the target token
   * @param {Types.Token} targetToken - The token for which to calculate the equivalent stake
   * @returns {Types.Amount} - The equivalent stake amount in the target token
   *
   * Example:
   * If a user has staked 100 Foresight tokens at a 5% rate, the equivalent
   * stake in Multi tokens at a 2% rate would be:
   * 100 * (0.02/0.05) = 100 * 0.4 = 40 Multi tokens
   */
  public func calculateEquivalentStake(
    knownStake : Types.Amount,
    knownRate : Types.Ratio,
    targetRate : Types.Ratio,
    targetToken : Types.Token,
  ) : Types.Amount {
    // Calculate the ratio between the target rate and known rate
    let rateRatio = RatioOperations.divide(targetRate, knownRate);

    // Apply this ratio to the known stake amount to get the equivalent stake
    let equivalentAmount = RatioOperations.applyToAmount(knownStake, rateRatio);

    // Return the result with the correct target token
    { token = targetToken; value = equivalentAmount.value };
  };

  /**
   * Calculates the adjusted stake rate based on the formula from the Foresight Protocol:
   * adjusted_rate = max(current_rate, total_stake / volume_limit)
   *
   * This function ensures that when total stakes exceed the volume limit,
   * the stake rate increases proportionally to maintain the system's
   * volume constraints.
   *
   * @param {Types.Ratio} currentRate - The current stake rate
   * @param {Nat} totalStake - The sum of all player stakes for this token type
   * @param {Nat} volumeLimit - The calculated volume limit (theta * M_start)
   * @returns {Types.Ratio} - The adjusted stake rate
   */
  public func calculateAdjustedStakeRate(
    currentRate : Types.Ratio,
    totalStake : Nat,
    volumeLimit : Nat,
  ) : Types.Ratio {
    if (volumeLimit == 0) {
      Debug.trap("Volume limit cannot be zero in calculateAdjustedStakeRate");
    };

    // Create a ratio from totalStake/volumeLimit using RatioOperations
    let calculatedRate = RatioOperations.fromNats(totalStake, volumeLimit);

    // Return the maximum of current rate and calculated rate
    RatioOperations.max(currentRate, calculatedRate);
  };

  /**
   * Calculates the token quantity a position can represent based on stake amount and rate.
   * Implements the formula: token_quantity = stake_amount / (adjusted_stake_rate * competition_price)
   *
   * This calculates how many tokens of the proposed type a player can acquire
   * based on their stake amount, the adjusted stake rate, and the competition price.
   *
   * @param {Types.Amount} stake - The stake amount
   * @param {Types.Ratio} adjustedStakeRate - The adjusted stake rate
   * @param {Types.Price} competitionPrice - The competition price for the proposed token
   * @returns {Types.Amount} - The token quantity that can be represented by this stake
   */
  public func calculateTokenQuantity(
    stake : Types.Amount,
    adjustedStakeRate : Types.Ratio,
    competitionPrice : Types.Price,
  ) : Types.Amount {
    // Validate that the stake token matches the quote token in the price
    TokenUtils.validateTokenMatch(stake.token, competitionPrice.quoteToken);

    // First, multiply the rate by the price value to get the denominator
    let denominator = RatioOperations.multiply(adjustedStakeRate, competitionPrice.value);

    // If denominator is zero, we can't proceed
    if (denominator.value == 0) {
      Debug.trap("Denominator in calculateTokenQuantity is zero");
    };

    // Then divide the stake by this product to get the token quantity
    // token_quantity = stake_amount / (adjusted_stake_rate * competition_price)
    let inverseMultiplier = RatioOperations.inverse(denominator);
    let tokenQuantity = RatioOperations.applyToAmount(stake, inverseMultiplier);

    // Return the result with the base token from the price
    { token = competitionPrice.baseToken; value = tokenQuantity.value };
  };
};
