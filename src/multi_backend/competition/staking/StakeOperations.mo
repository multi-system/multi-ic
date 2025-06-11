import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";

import Types "../../types/Types";
import Error "../../error/Error";
import StakeCalculator "./StakeCalculator";
import CompetitionEntryStore "../CompetitionEntryStore";
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
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    govStake : Types.Amount,
    proposedToken : Types.Token,
  ) : Result.Result<SubmissionQuantities, Error.CompetitionError> {
    // Verify competition is active
    if (competitionEntry.getStatus() != #AcceptingStakes) {
      return #err(#InvalidPhase({ current = debug_show (competitionEntry.getStatus()); required = "AcceptingStakes" }));
    };

    // Validate the Gov token type
    switch (StakeValidation.validateTokenType(govStake, competitionEntry.getGovToken())) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    // Check if token is approved first
    if (not competitionEntry.isTokenApproved(proposedToken)) {
      return #err(#TokenNotApproved(proposedToken));
    };

    // Get the competition price for the proposed token (now returns Price directly)
    let price = competitionEntry.getCompetitionPrice(proposedToken);

    // Calculate the equivalent Multi stake using the current adjusted rates
    let multiStake = StakeCalculator.calculateEquivalentStake(
      govStake,
      competitionEntry.getAdjustedGovRate(),
      competitionEntry.getAdjustedMultiRate(),
      competitionEntry.getMultiToken(),
    );

    // Calculate token quantity using the current adjusted stake rate
    let tokenQuantity = StakeCalculator.calculateTokenQuantity(
      multiStake,
      competitionEntry.getAdjustedMultiRate(),
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
   * Updates stake rates in the competition entry based on the provided total stakes
   * and volume limit. This is used during both stake submission processing
   * and submission finalization.
   *
   * @param competitionEntry The competition entry to update
   * @param totalGovStake The total governance stake amount
   * @param totalMultiStake The total multi stake amount
   * @param volumeLimit The calculated volume limit
   * @returns A tuple with the adjusted (govRate, multiRate)
   */
  public func updateAdjustedStakeRates(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    totalGovStake : Nat,
    totalMultiStake : Nat,
    volumeLimit : Nat,
  ) : (Types.Ratio, Types.Ratio) {
    // Get current adjusted rates from the competition entry
    let currentGovRate = competitionEntry.getAdjustedGovRate();
    let currentMultiRate = competitionEntry.getAdjustedMultiRate();

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

    // Update the rates in the competition entry
    competitionEntry.updateStakeRates(updatedGovRate, updatedMultiRate);

    // Return the new rates
    (updatedGovRate, updatedMultiRate);
  };

  /**
   * Calculates the adjusted stake rate for a specific token type without
   * updating the competition entry. Useful for preview calculations.
   *
   * @param competitionEntry The competition entry with current rates
   * @param isGovToken Whether we're calculating for governance token (true) or multi token (false)
   * @param totalStake The total stake amount for the specified token type
   * @param volumeLimit The calculated volume limit
   * @returns The adjusted stake rate
   */
  public func calculateAdjustedStakeRate(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    isGovToken : Bool,
    totalStake : Nat,
    volumeLimit : Nat,
  ) : Types.Ratio {
    let currentRate = if (isGovToken) {
      competitionEntry.getAdjustedGovRate();
    } else {
      competitionEntry.getAdjustedMultiRate();
    };

    StakeCalculator.calculateAdjustedStakeRate(
      currentRate,
      totalStake,
      volumeLimit,
    );
  };
};
