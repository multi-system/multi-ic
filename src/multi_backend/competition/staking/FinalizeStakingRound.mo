import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

import Types "../../types/Types";
import Error "../../error/Error";
import SubmissionTypes "../../types/SubmissionTypes";
import BackingTypes "../../types/BackingTypes";
import SystemStakeTypes "../../types/SystemStakeTypes";
import StakeCalculator "./StakeCalculator";
import StakeOperations "./StakeOperations";
import CompetitionEntryStore "../CompetitionEntryStore";
import SubmissionOperations "./SubmissionOperations";
import SystemStakeOperations "./SystemStakeOperations";
import StakeTokenTypes "../../types/StakeTokenTypes";

module {
  /**
   * Result of the staking round finalization process with flexible stake tokens
   */
  public type FinalizationResult = {
    initialRates : [(Types.Token, Types.Ratio)];
    finalRates : [(Types.Token, Types.Ratio)];
    totalStakes : [(Types.Token, Nat)];
    volumeLimit : Nat;
    stakedSubmissionsCount : Nat;
    adjustmentSuccessCount : Nat;
    adjustmentFailureCount : Nat;
    systemStake : SystemStakeTypes.SystemStake;
  };

  /**
   * Finalizes the staking round with flexible stake tokens.
   *
   * @param competitionEntry The competition entry store with configuration and submissions
   * @param getCirculatingSupply Function to get current circulating supply
   * @param getBackingTokens Function to retrieve backing tokens
   * @returns Result with finalization stats or an error
   */
  public func finalizeRound(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) : Result.Result<FinalizationResult, Error.CompetitionError> {

    let stakeVault = competitionEntry.getStakeVault();

    // Validate competition state
    if (competitionEntry.getStatus() != #AcceptingStakes) {
      return #err(#InvalidPhase({ current = debug_show (competitionEntry.getStatus()); required = "AcceptingStakes" }));
    };

    // Calculate volume limit
    let volumeLimit = competitionEntry.calculateVolumeLimit(getCirculatingSupply);

    // Get initial rates for all stake tokens
    let stakeConfigs = competitionEntry.getStakeTokenConfigs();
    let initialRates = Array.map<StakeTokenTypes.StakeTokenConfig, (Types.Token, Types.Ratio)>(
      stakeConfigs,
      func(config) = (config.token, competitionEntry.getEffectiveRate(config.token)),
    );

    // Get current total stakes from vault
    let totalStakes = stakeVault.getAllTotalStakes();

    // Update all stake rates based on totals and volume limit
    let updatedRates = StakeOperations.updateAllStakeRates(
      competitionEntry,
      volumeLimit,
    );

    // Get all Staked submissions to adjust
    let stakedSubmissions = competitionEntry.getSubmissionsByStatus(#Staked);
    let stakedSubmissionsCount = stakedSubmissions.size();

    var adjustmentSuccessCount = 0;
    var adjustmentFailureCount = 0;

    // Process each submission with updated rates
    for (submission in stakedSubmissions.vals()) {
      switch (
        SubmissionOperations.adjustSubmissionPostRound(
          competitionEntry,
          stakeVault,
          submission.id,
          updatedRates,
        )
      ) {
        case (#ok(_)) { adjustmentSuccessCount += 1 };
        case (#err(_)) { adjustmentFailureCount += 1 };
      };
    };

    // Calculate system stakes for all configured tokens
    let backingPairs = getBackingTokens();

    let systemStake = SystemStakeOperations.calculateSystemStakes(
      competitionEntry,
      totalStakes,
      volumeLimit,
      backingPairs,
    );

    competitionEntry.setSystemStake(systemStake);

    #ok({
      initialRates = initialRates;
      finalRates = updatedRates;
      totalStakes = totalStakes;
      volumeLimit = volumeLimit;
      stakedSubmissionsCount = stakedSubmissionsCount;
      adjustmentSuccessCount = adjustmentSuccessCount;
      adjustmentFailureCount = adjustmentFailureCount;
      systemStake = systemStake;
    });
  };
};
