import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";

import Types "../../types/Types";
import Error "../../error/Error";
import StakeCalculator "./StakeCalculator";
import CompetitionStore "../CompetitionStore";
import SubmissionTypes "../../types/SubmissionTypes";
import StakeValidation "./StakeValidation";

/**
 * StakeOperations provides common functionality for stake operations
 * that can be shared between different modules like StakingManager
 * and FinalizeStakingRound.
 */
module {
  // Define a local type for submission quantities to simplify the return value
  public type SubmissionQuantities = {
    govStake : Types.Amount;
    multiStake : Types.Amount;
    tokenQuantity : Types.Amount;
    proposedToken : Types.Token;
  };

  /**
   * Calculates the quantities for a submission based on current stake rates
   * including basic validation but without recalculating rates.
   */
  public func calculateSubmission(
    store : CompetitionStore.CompetitionStore,
    govStake : Types.Amount,
    proposedToken : Types.Token,
  ) : Result.Result<SubmissionQuantities, Error.CompetitionError> {
    // Verify competition is active
    if (not store.isCompetitionActive()) {
      return #err(#CompetitionNotActive);
    };

    // Validate the Gov token type
    switch (StakeValidation.validateTokenType(govStake, store.getGovToken())) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    // Get the competition price for the proposed token
    let price = switch (store.getCompetitionPrice(proposedToken)) {
      case (null) {
        return #err(#TokenNotApproved(proposedToken));
      };
      case (?p) {
        p;
      };
    };

    // Calculate the equivalent Multi stake
    let multiStake = StakeCalculator.calculateEquivalentStake(
      govStake,
      store.getGovRate(),
      store.getMultiRate(),
      store.getMultiToken(),
    );

    // Calculate token quantity using the current stake rate
    let tokenQuantity = StakeCalculator.calculateTokenQuantity(
      multiStake,
      store.getMultiRate(),
      price,
    );

    #ok({
      govStake;
      multiStake;
      tokenQuantity;
      proposedToken;
    });
  };

  /**
   * Updates stake rates in the store based on the provided total stakes
   * and volume limit. This is used during both stake submission processing
   * and submission finalization.
   *
   * @param store The competition store to update
   * @param totalGovStake The total governance stake amount
   * @param totalMultiStake The total multi stake amount
   * @param volumeLimit The calculated volume limit
   * @returns A tuple with the adjusted (govRate, multiRate)
   */
  public func updateAdjustedStakeRates(
    store : CompetitionStore.CompetitionStore,
    totalGovStake : Nat,
    totalMultiStake : Nat,
    volumeLimit : Nat,
  ) : (Types.Ratio, Types.Ratio) {
    // Get current rates from the store
    let currentGovRate = store.getGovRate();
    let currentMultiRate = store.getMultiRate();

    // Calculate adjusted rates based on current stakes and limit
    let updatedGovRate = StakeCalculator.calculateAdjustedStakeRate(
      currentGovRate,
      totalGovStake,
      volumeLimit,
    );

    let updatedMultiRate = StakeCalculator.calculateAdjustedStakeRate(
      currentMultiRate,
      totalMultiStake,
      volumeLimit,
    );

    // Update the rates in the store
    store.updateStakeRates(updatedGovRate, updatedMultiRate);

    // Return the new rates
    (updatedGovRate, updatedMultiRate);
  };

  /**
   * Calculates the adjusted stake rate for a specific token type without
   * updating the store. Useful for preview calculations.
   *
   * @param store The competition store with current rates
   * @param isGovToken Whether we're calculating for governance token (true) or multi token (false)
   * @param totalStake The total stake amount for the specified token type
   * @param volumeLimit The calculated volume limit
   * @returns The adjusted stake rate
   */
  public func calculateAdjustedStakeRate(
    store : CompetitionStore.CompetitionStore,
    isGovToken : Bool,
    totalStake : Nat,
    volumeLimit : Nat,
  ) : Types.Ratio {
    let currentRate = if (isGovToken) {
      store.getGovRate();
    } else {
      store.getMultiRate();
    };

    StakeCalculator.calculateAdjustedStakeRate(
      currentRate,
      totalStake,
      volumeLimit,
    );
  };
};
