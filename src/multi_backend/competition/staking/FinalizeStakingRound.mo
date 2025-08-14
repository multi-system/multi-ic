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

/**
 * FinalizeStakingRound handles the end of a staking competition round.
 * It adjusts stake rates based on total stakes and volume limit,
 * then updates Staked submissions to Finalized status.
 * Additionally, it calculates the system's stake for the competition.
 */
module {
  /**
   * Result of the staking round finalization process
   */
  public type FinalizationResult = {
    initialGovRate : Types.Ratio;
    finalGovRate : Types.Ratio;
    initialMultiRate : Types.Ratio;
    finalMultiRate : Types.Ratio;
    totalGovStaked : Nat;
    totalMultiStaked : Nat;
    volumeLimit : Nat;
    stakedSubmissionsCount : Nat;
    adjustmentSuccessCount : Nat;
    adjustmentFailureCount : Nat;
    systemStake : SystemStakeTypes.SystemStake;
  };

  /**
   * Finalizes the staking round by:
   * 1. Calculating adjusted stake rates based on total stakes and volume limit
   * 2. Processing all Staked submissions with the adjusted rates
   * 3. Calculating the system's stake and phantom positions
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
    // Get the stake vault from the competition entry
    let stakeVault = competitionEntry.getStakeVault();

    // Validate competition state
    if (competitionEntry.getStatus() != #AcceptingStakes) {
      return #err(#InvalidPhase({ current = debug_show (competitionEntry.getStatus()); required = "AcceptingStakes" }));
    };

    // Get the volume limit (theta * M_start)
    let volumeLimit = competitionEntry.calculateVolumeLimit(getCirculatingSupply);

    // Get the initial rates
    let initialGovRate = competitionEntry.getGovRate();
    let initialMultiRate = competitionEntry.getMultiRate();

    // Get current total stakes from the stake vault
    let totalGovStaked = stakeVault.getTotalGovernanceStake();
    let totalMultiStaked = stakeVault.getTotalMultiStake();

    // Update both stake rates in the store using StakeOperations
    let (updatedGovRate, updatedMultiRate) = StakeOperations.updateAdjustedStakeRates(
      competitionEntry,
      totalGovStaked,
      totalMultiStaked,
      volumeLimit,
    );

    // Get all Staked submissions that need to be adjusted
    let stakedSubmissions = competitionEntry.getSubmissionsByStatus(#Staked);
    let stakedSubmissionsCount = stakedSubmissions.size();

    // Track success and failure counts
    var adjustmentSuccessCount = 0;
    var adjustmentFailureCount = 0;

    // Process each Staked submission to adjust its quantities based on updated rates
    for (submission in stakedSubmissions.vals()) {
      switch (
        SubmissionOperations.adjustSubmissionPostRound(
          competitionEntry,
          stakeVault,
          submission.id,
          updatedGovRate,
          updatedMultiRate,
        )
      ) {
        case (#ok(_)) {
          adjustmentSuccessCount += 1;
        };
        case (#err(_)) {
          adjustmentFailureCount += 1;
        };
      };
    };

    // Calculate the system stake and phantom positions using SystemStakeOperations
    // This represents the system's participation in the competition
    let backingPairs = getBackingTokens();

    let systemStake = SystemStakeOperations.calculateSystemStakes(
      competitionEntry,
      competitionEntry.getConfig().systemStakeGov,
      competitionEntry.getConfig().systemStakeMulti,
      totalGovStaked,
      totalMultiStaked,
      volumeLimit,
      backingPairs,
    );

    // Set the system stake in the competition entry
    competitionEntry.setSystemStake(systemStake);

    // Return the finalization result
    #ok({
      initialGovRate;
      finalGovRate = updatedGovRate;
      initialMultiRate;
      finalMultiRate = updatedMultiRate;
      totalGovStaked;
      totalMultiStaked;
      volumeLimit;
      stakedSubmissionsCount;
      adjustmentSuccessCount;
      adjustmentFailureCount;
      systemStake;
    });
  };
};
