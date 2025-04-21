import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Types "../../types/Types";
import BackingTypes "../../types/BackingTypes";
import SystemStakeTypes "../../types/SystemStakeTypes";
import SystemStakeCalculator "./SystemStakeCalculator";
import CompetitionEntryStore "../CompetitionEntryStore";

/**
 * SystemStakeHelper provides higher-level functions for working with system stakes
 * that combine multiple calculations from SystemStakeCalculator.
 */
module {
  /**
   * Calculates both governance and multi token system stakes along with their phantom positions.
   *
   * @param competitionEntry The competition entry with current state
   * @param govMultiplier The governance token system multiplier
   * @param multiMultiplier The multi token system multiplier
   * @param totalGovStake The total player governance stake
   * @param totalMultiStake The total player multi stake
   * @param volumeLimit The calculated volume limit
   * @param backingPairs The current backing pairs representing token distribution
   * @returns Complete information about system stakes and phantom positions
   */
  public func calculateSystemStakes(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    govMultiplier : Types.Ratio,
    multiMultiplier : Types.Ratio,
    totalGovStake : Nat,
    totalMultiStake : Nat,
    volumeLimit : Nat,
    backingPairs : [BackingTypes.BackingPair],
  ) : SystemStakeTypes.SystemStake {

    // Calculate governance system stake
    let govSystemStake = SystemStakeCalculator.calculateSystemStake(
      totalGovStake,
      govMultiplier,
      competitionEntry.getGovRate(),
      volumeLimit,
      competitionEntry.getGovToken(),
    );

    // Calculate multi system stake
    let multiSystemStake = SystemStakeCalculator.calculateSystemStake(
      totalMultiStake,
      multiMultiplier,
      competitionEntry.getMultiRate(),
      volumeLimit,
      competitionEntry.getMultiToken(),
    );

    // Calculate phantom positions based on multi token
    // (since these positions represent how the system would distribute assets)
    let phantomPositions = SystemStakeCalculator.calculatePhantomPositions(
      multiSystemStake,
      competitionEntry.getMultiRate(),
      backingPairs,
    );

    {
      govSystemStake;
      multiSystemStake;
      phantomPositions;
    };
  };
};
