import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import BackingTypes "../../types/BackingTypes";
import RatioOperations "../../financial/RatioOperations";
import TokenUtils "../../financial/TokenUtils";

module {
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
    // Calculate maximum stake at base rate: theta * M_start * r
    let maxStakeAtBaseRate = RatioOperations.applyToAmount(
      { token = tokenType; value = volumeLimit },
      baseRate,
    ).value;

    // Take minimum of player stake and max stake
    let effectiveStake = Nat.min(totalPlayerStake, maxStakeAtBaseRate);

    // Apply multiplier: lambda * min(...)
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
    // Calculate total backing units for proportions
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
        // Calculate proportion for this token
        let proportion = RatioOperations.fromNats(pair.backingUnit, totalBackingUnits);

        // Calculate token-specific system stake: s_k = S * proportion
        let tokenStake = RatioOperations.applyToAmount(systemStake, proportion);

        // Calculate phantom position: q_k = s_k / r
        let phantomQuantity = RatioOperations.applyToAmount(
          tokenStake,
          RatioOperations.inverse(stakeRate),
        );

        (pair.token, { token = pair.token; value = phantomQuantity.value });
      },
    );
  };
};
