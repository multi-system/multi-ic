import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import BackingTypes "../../types/BackingTypes";
import RatioOperations "../../financial/RatioOperations";
import TokenUtils "../../financial/TokenUtils";

// SystemStakeCalculator provides calculations for system stake amounts and phantom positions
// as specified in section 4.3.1 of the Foresight protocol specification.
module {
  /**
   * Calculates the system stake amount based on the formula:
   * S = lambda * min(total_player_stake, theta * M_start * r)
   *
   * @param totalPlayerStake The sum of all player stakes for this token type
   * @param multiplier The system stake multiplier (lambda)
   * @param baseRate The base stake rate (r)
   * @param volumeLimit The calculated volume limit (theta * M_start)
   * @param tokenType The token type for the result
   * @returns The system stake amount
   */
  public func calculateSystemStake(
    totalPlayerStake : Nat,
    multiplier : Types.Ratio,
    baseRate : Types.Ratio,
    volumeLimit : Nat,
    tokenType : Types.Token,
  ) : Types.Amount {
    // Calculate the maximum stake at base rate: theta * M_start * r
    let maxStakeAtBaseRate = RatioOperations.applyToAmount(
      { token = tokenType; value = volumeLimit },
      baseRate,
    ).value;

    // Take the minimum of player stake and max stake
    let effectiveStake = Nat.min(totalPlayerStake, maxStakeAtBaseRate);

    // Apply the multiplier: lambda * min(...)
    // Create an Amount to use applyToAmount instead of the non-existent applyToNat
    let effectiveStakeAmount = { token = tokenType; value = effectiveStake };
    let systemStakeAmount = RatioOperations.applyToAmount(effectiveStakeAmount, multiplier);

    // Return as an Amount
    { token = tokenType; value = systemStakeAmount.value };
  };

  /**
   * Calculates the phantom positions for each backing token based on the system stake.
   * Phantom positions represent hypothetical trades as described in section 4.3.1:
   * q_k = s_k / r
   *
   * Where:
   * - q_k is the phantom quantity for token k
   * - s_k is the system stake for token k
   * - r is the current stake rate
   *
   * @param systemStake The total system stake (for either gov or multi token)
   * @param stakeRate The current stake rate for the token type
   * @param backingPairs The current backing pairs representing token distribution
   * @returns Array of phantom positions for each backing token
   */
  public func calculatePhantomPositions(
    systemStake : Types.Amount,
    stakeRate : Types.Ratio,
    backingPairs : [BackingTypes.BackingPair],
  ) : [(Types.Token, Types.Amount)] {
    // First calculate the total backing units to determine proportions
    let totalBackingUnits = Array.foldLeft<BackingTypes.BackingPair, Nat>(
      backingPairs,
      0,
      func(acc, pair) { acc + pair.backingUnit },
    );

    if (totalBackingUnits == 0) {
      return [];
    };

    // Calculate phantom positions for each backing token
    Array.map<BackingTypes.BackingPair, (Types.Token, Types.Amount)>(
      backingPairs,
      func(pair) {
        // Calculate proportion of system stake for this token
        let proportion = RatioOperations.fromNats(pair.backingUnit, totalBackingUnits);

        // Calculate token-specific system stake: s_k = S * proportion
        let tokenStake = RatioOperations.applyToAmount(systemStake, proportion);

        // Calculate phantom position: q_k = s_k / r
        let phantomQuantity = RatioOperations.applyToAmount(
          tokenStake,
          RatioOperations.inverse(stakeRate),
        );

        // Return token and its phantom quantity
        (pair.token, { token = pair.token; value = phantomQuantity.value });
      },
    );
  };
};
