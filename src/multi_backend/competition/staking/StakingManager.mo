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
  /**
   * Helper type for submission quantities
   */
  public type SubmissionQuantities = {
    tokenQuantity : Types.Amount;
    govStake : Types.Amount;
    multiStake : Types.Amount;
  };

  public class StakingManager(
    competitionEntry : CompetitionEntryStore.CompetitionEntryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) {
    // Get the StakeVault from the competition entry
    private func getStakeVault() : StakeVault.StakeVault {
      competitionEntry.getStakeVault();
    };

    // Create a submission using SubmissionOperations
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
        quantities.govStake,
        quantities.multiStake,
      );
    };

    // Handle stake requests - calculate and process immediately
    public func acceptStakeRequest(
      govStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount }, Error.CompetitionError> {
      // Calculate the submission quantities using StakeOperations
      switch (StakeOperations.calculateSubmission(competitionEntry, govStake, proposedToken)) {
        case (#err(e)) return #err(e);
        case (#ok(quantities)) {
          // Create a submission object for direct processing
          let submission = createSubmission(account, quantities, proposedToken);

          // Process directly using SubmissionOperations
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

    // Finalize a single submission (for testing)
    public func finalizeSubmission(
      submissionId : SubmissionTypes.SubmissionId,
      updatedGovRate : Types.Ratio,
      updatedMultiRate : Types.Ratio,
    ) : Result.Result<SubmissionTypes.Submission, Error.CompetitionError> {
      SubmissionOperations.adjustSubmissionPostRound(
        competitionEntry,
        getStakeVault(),
        submissionId,
        updatedGovRate,
        updatedMultiRate,
      );
    };

    // Finalize the current staking round
    public func finalizeRound() : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      FinalizeStakingRound.finalizeRound(
        competitionEntry,
        getCirculatingSupply,
        getBackingTokens,
      );
    };
  };
};
