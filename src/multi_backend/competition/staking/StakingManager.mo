import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Array "mo:base/Array";

import Types "../../types/Types";
import Error "../../error/Error";
import BackingTypes "../../types/BackingTypes";
import CompetitionEntryStore "../CompetitionEntryStore";
import SubmissionTypes "../../types/SubmissionTypes";
import StakeOperations "./StakeOperations";
import StakeVault "./StakeVault";
import SubmissionOperations "./SubmissionOperations";
import FinalizeStakingRound "./FinalizeStakingRound";

module {
  public type SubmissionQuantities = {
    tokenQuantity : Types.Amount;
    stakes : [(Types.Token, Types.Amount)];
  };

  public class StakingManager(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) {

    private func getStakeVault() : StakeVault.StakeVault {
      competitionEntry.getStakeVault();
    };

    private func createSubmission(
      account : Types.Account,
      quantities : SubmissionQuantities,
      token : Types.Token,
    ) : SubmissionTypes.Submission {
      SubmissionOperations.createSubmission(
        competitionEntry,
        account,
        token,
        quantities.tokenQuantity.value,
        quantities.stakes,
      );
    };

    /**
     * Accept a stake request with fully agnostic stake token support.
     * User stakes with the first configured stake token.
     *
     * @param inputStake The stake amount in the first configured stake token
     * @param account The account making the submission
     * @param proposedToken The token to add to the reserve
     * @returns Submission ID and calculated token quantity
     */
    public func acceptStakeRequest(
      inputStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount }, Error.CompetitionError> {

      // Calculate submission quantities for all stake tokens
      switch (StakeOperations.calculateSubmission(competitionEntry, inputStake, proposedToken)) {
        case (#err(e)) return #err(e);
        case (#ok(quantities)) {
          // Create submission with all calculated stakes
          let submission = createSubmission(
            account,
            {
              tokenQuantity = quantities.tokenQuantity;
              stakes = quantities.stakes;
            },
            proposedToken,
          );

          // Process the submission
          switch (SubmissionOperations.processSubmission(competitionEntry, getStakeVault(), submission)) {
            case (#err(e)) return #err(e);
            case (#ok(_)) {
              #ok({
                submissionId = submission.id;
                tokenQuantity = quantities.tokenQuantity;
              });
            };
          };
        };
      };
    };

    /**
     * Finalize a single submission with updated rates for all stake tokens.
     *
     * @param submissionId The submission to finalize
     * @param updatedRates Array of updated rates for all stake tokens
     * @returns The finalized submission
     */
    public func finalizeSubmission(
      submissionId : SubmissionTypes.SubmissionId,
      updatedRates : [(Types.Token, Types.Ratio)],
    ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
      SubmissionOperations.adjustSubmissionPostRound(
        competitionEntry,
        getStakeVault(),
        submissionId,
        updatedRates,
      );
    };

    /**
     * Finalize the current staking round.
     *
     * @returns Finalization result with stats for all stake tokens
     */
    public func finalizeRound() : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      FinalizeStakingRound.finalizeRound(
        competitionEntry,
        getCirculatingSupply,
        getBackingTokens,
      );
    };
  };
};
