import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Types "../../types/Types";
import Error "../../error/Error";
import StakeCalculator "./StakeCalculator";
import CompetitionEntryStore "../CompetitionEntryStore";
import SubmissionTypes "../../types/SubmissionTypes";
import StakeValidation "./StakeValidation";

module {
  public type SubmissionQuantities = {
    stakes : [(Types.Token, Types.Amount)];
    tokenQuantity : Types.Amount;
    proposedToken : Types.Token;
  };

  /**
   * Calculates submission quantities based on input stake in first configured token.
   * Calculates equivalent stakes for all other configured tokens.
   *
   * @param competitionEntry The competition entry store
   * @param inputStake The stake amount in the first configured stake token
   * @param proposedToken The token being proposed for the reserve
   * @returns All calculated stake amounts and token quantity
   */
  public func calculateSubmission(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    inputStake : Types.Amount,
    proposedToken : Types.Token,
  ) : Result.Result<SubmissionQuantities, Error.CompetitionError> {

    // Verify competition is active
    if (competitionEntry.getStatus() != #AcceptingStakes) {
      return #err(#InvalidPhase({ current = debug_show (competitionEntry.getStatus()); required = "AcceptingStakes" }));
    };

    // Get stake token configurations
    let stakeConfigs = competitionEntry.getStakeTokenConfigs();
    if (stakeConfigs.size() == 0) {
      Debug.trap("No stake tokens configured");
    };

    // Verify input token matches first configured stake token
    let firstStakeToken = stakeConfigs[0].token;
    if (not Principal.equal(inputStake.token, firstStakeToken)) {
      return #err(#InvalidSubmission({ reason = "Must stake with first configured token: " # Principal.toText(firstStakeToken) }));
    };

    // Check if proposed token is approved
    if (not competitionEntry.isTokenApproved(proposedToken)) {
      return #err(#TokenNotApproved(proposedToken));
    };

    // Get the competition price for the proposed token
    let price = competitionEntry.getCompetitionPrice(proposedToken);

    // Calculate stakes for all configured tokens
    let stakesBuffer = Buffer.Buffer<(Types.Token, Types.Amount)>(stakeConfigs.size());
    let inputRate = competitionEntry.getEffectiveRate(firstStakeToken);

    // Add the input stake first
    stakesBuffer.add((firstStakeToken, inputStake));

    // Calculate equivalent stakes for all other tokens
    for (i in Iter.range(1, stakeConfigs.size() - 1)) {
      let config = stakeConfigs[i];
      let targetRate = competitionEntry.getEffectiveRate(config.token);

      let equivalentStake = StakeCalculator.calculateEquivalentStake(
        inputStake,
        inputRate,
        targetRate,
        config.token,
      );

      stakesBuffer.add((config.token, equivalentStake));
    };

    let stakes = Buffer.toArray(stakesBuffer);

    // Calculate token quantity using the first stake (any would work due to normalization)
    let tokenQuantity = StakeCalculator.calculateTokenQuantity(
      inputStake,
      inputRate,
      price,
    );

    #ok({
      stakes = stakes;
      tokenQuantity = tokenQuantity;
      proposedToken = proposedToken;
    });
  };

  /**
   * Updates all stake rates based on total stakes and volume limit.
   *
   * @param competitionEntry The competition entry to update
   * @param volumeLimit The calculated volume limit
   * @returns Array of updated rates for each stake token
   */
  public func updateAllStakeRates(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    volumeLimit : Nat,
  ) : [(Types.Token, Types.Ratio)] {

    let stakeConfigs = competitionEntry.getStakeTokenConfigs();
    let ratesBuffer = Buffer.Buffer<(Types.Token, Types.Ratio)>(stakeConfigs.size());

    for (config in stakeConfigs.vals()) {
      let totalStake = competitionEntry.getTotalStake(config.token);
      let currentRate = competitionEntry.getEffectiveRate(config.token);

      let updatedRate = StakeCalculator.calculateAdjustedStakeRate(
        currentRate,
        totalStake,
        volumeLimit,
      );

      ratesBuffer.add((config.token, updatedRate));
    };

    let newRates = Buffer.toArray(ratesBuffer);

    // Update all rates in the competition entry
    ignore competitionEntry.updateAllStakeRates(newRates);

    newRates;
  };
};
