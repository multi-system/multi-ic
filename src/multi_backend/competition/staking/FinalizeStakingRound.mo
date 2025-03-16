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
import CompetitionStore "../CompetitionStore";
import StakeVault "./StakeVault";
import SubmissionOperations "./SubmissionOperations";
import SystemStakeOperations "./SystemStakeOperations";

/**
 * FinalizeStakingRound handles the end of a staking competition round.
 * It processes submissions in the PreRound status, adjusts stake rates based on
 * total stakes and volume limit, then updates ActiveRound submissions to PostRound status.
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
    activeSubmissionsCount : Nat;
    adjustmentSuccessCount : Nat;
    adjustmentFailureCount : Nat;
    preRoundProcessedCount : Nat;
    preRoundSuccessCount : Nat;
    preRoundFailureCount : Nat;
    systemStake : SystemStakeTypes.SystemStake;
  };

  /**
   * Helper function to determine the rejection reason from an error
   */
  private func determineRejectionReason(error : Error.CompetitionError) : SubmissionTypes.RejectionReason {
    switch (error) {
      case (#InsufficientStake(_)) {
        #InsufficientBalance;
      };
      case (#TokenNotApproved(_)) {
        #InvalidToken;
      };
      case (#CompetitionNotActive) {
        #CompetitionNotActive;
      };
      case (#OperationFailed(reason)) {
        #Other(reason);
      };
      case (#InvalidPhase(_)) {
        #Other("Invalid phase");
      };
      case (_) {
        #Other("Unknown error");
      };
    };
  };

  /**
   * Finalizes the staking round by:
   * 1. Processing all PreRound submissions
   * 2. Calculating adjusted stake rates based on total stakes and volume limit
   * 3. Processing all ActiveRound submissions with the adjusted rates
   * 4. Calculating the system's stake and phantom positions
   *
   * @param store The competition store with configuration and submissions
   * @param stakeVault The stake vault module
   * @param getCirculatingSupply Function to get current circulating supply
   * @param getBackingTokens Function to retrieve backing tokens
   * @returns Result with finalization stats or an error
   */
  public func finalizeRound(
    store : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) : Result.Result<FinalizationResult, Error.CompetitionError> {
    // Validate competition state
    if (not store.hasInitialized()) {
      return #err(#OperationFailed("Competition system not initialized"));
    };

    if (not store.isCompetitionActive()) {
      return #err(#CompetitionNotActive);
    };

    // Process all PreRound submissions
    var preRoundProcessedCount = 0;
    var preRoundSuccessCount = 0;
    var preRoundFailureCount = 0;

    let preRoundSubmissions = store.getSubmissionsByStatus(#PreRound);

    // Process each PreRound submission
    for (submission in preRoundSubmissions.vals()) {
      preRoundProcessedCount += 1;

      // Process the submission and track results
      switch (SubmissionOperations.processSubmission(store, stakeVault, submission)) {
        case (#err(_)) {
          preRoundFailureCount += 1;
        };
        case (#ok(_)) {
          preRoundSuccessCount += 1;
        };
      };
    };

    // Get the volume limit (theta * M_start)
    let volumeLimit = store.getVolumeLimit(getCirculatingSupply);

    // Get the initial rates
    let initialGovRate = store.getGovRate();
    let initialMultiRate = store.getMultiRate();

    // Get current total stakes from the stake vault
    let totalGovStaked = stakeVault.getTotalGovernanceStake();
    let totalMultiStaked = stakeVault.getTotalMultiStake();

    // Update both stake rates in the store using StakeOperations
    let (updatedGovRate, updatedMultiRate) = StakeOperations.updateAdjustedStakeRates(
      store,
      totalGovStaked,
      totalMultiStaked,
      volumeLimit,
    );

    // Get all active submissions that need to be adjusted
    let activeSubmissions = store.getSubmissionsByStatus(#ActiveRound);
    let activeSubmissionsCount = activeSubmissions.size();

    // Track success and failure counts
    var adjustmentSuccessCount = 0;
    var adjustmentFailureCount = 0;

    // Process each active submission to adjust its quantities based on updated rates
    for (submission in activeSubmissions.vals()) {
      switch (
        SubmissionOperations.adjustSubmissionPostRound(
          store,
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
      store,
      store.getSystemStakeGov(),
      store.getSystemStakeMulti(),
      totalGovStaked,
      totalMultiStaked,
      volumeLimit,
      backingPairs,
    );

    // Return the finalization result
    #ok({
      initialGovRate;
      finalGovRate = updatedGovRate;
      initialMultiRate;
      finalMultiRate = updatedMultiRate;
      totalGovStaked;
      totalMultiStaked;
      volumeLimit;
      activeSubmissionsCount;
      adjustmentSuccessCount;
      adjustmentFailureCount;
      preRoundProcessedCount;
      preRoundSuccessCount;
      preRoundFailureCount;
      systemStake;
    });
  };
};
