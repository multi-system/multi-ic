import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";

import Types "../../types/Types";
import BackingTypes "../../types/BackingTypes";
import SystemStakeTypes "../../types/SystemStakeTypes";
import StakeCalculator "./StakeCalculator";
import CompetitionEntryStore "../CompetitionEntryStore";
import TokenAccessHelper "../../helper/TokenAccessHelper";

module {
  /**
   * Calculates system stakes for all configured stake tokens.
   *
   * @param competitionEntry The competition entry with current state
   * @param totalStakes Array of total player stakes for each token
   * @param volumeLimit The calculated volume limit
   * @param backingPairs The current backing pairs representing token distribution
   * @returns Complete information about system stakes and phantom positions
   */
  public func calculateSystemStakes(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    totalStakes : [(Types.Token, Nat)],
    volumeLimit : Nat,
    backingPairs : [BackingTypes.BackingPair],
  ) : SystemStakeTypes.SystemStake {

    let stakeConfigs = competitionEntry.getStakeTokenConfigs();
    let systemStakesBuffer = Buffer.Buffer<(Types.Token, Types.Amount)>(stakeConfigs.size());

    // Calculate system stake for each configured token
    for (config in stakeConfigs.vals()) {
      // Find total stake for this token
      let totalStake = switch (TokenAccessHelper.findInTokenArray(totalStakes, config.token)) {
        case (null) { 0 };
        case (?amount) { amount };
      };

      // Calculate system stake for this token
      let systemStake = StakeCalculator.calculateSystemStake(
        totalStake,
        config.systemMultiplier,
        config.baseRate,
        volumeLimit,
        config.token,
      );

      systemStakesBuffer.add((config.token, systemStake));
    };

    let systemStakes = Buffer.toArray(systemStakesBuffer);

    // For phantom positions, use the first configured stake token
    // (any would work due to rate normalization)
    if (stakeConfigs.size() == 0) {
      Debug.trap("No stake tokens configured");
    };

    let phantomBaseToken = stakeConfigs[0].token;
    let phantomStakeOpt = TokenAccessHelper.findInTokenArray(systemStakes, phantomBaseToken);

    let phantomSystemStake = switch (phantomStakeOpt) {
      case (null) { { token = phantomBaseToken; value = 0 } };
      case (?amount) { amount };
    };

    let phantomRate = competitionEntry.getEffectiveRate(phantomBaseToken);

    let phantomPositions = StakeCalculator.calculatePhantomPositions(
      phantomSystemStake,
      phantomRate,
      backingPairs,
    );

    {
      systemStakes = systemStakes;
      phantomPositions = phantomPositions;
    };
  };
};
