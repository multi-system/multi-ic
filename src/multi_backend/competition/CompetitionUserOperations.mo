import Result "mo:base/Result";
import Debug "mo:base/Debug";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionRegistryStore "./CompetitionRegistryStore";
import CompetitionEntryStore "./CompetitionEntryStore";
import StakingManager "./staking/StakingManager";
import BackingTypes "../types/BackingTypes";
import SubmissionTypes "../types/SubmissionTypes";

/**
 * CompetitionUserOperations handles all user-facing operations for competitions.
 * This serves as the main entry point for user interactions with the competition system.
 */
module {
  public class CompetitionUserOperations(
    registryStore : CompetitionRegistryStore.CompetitionRegistryStore,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
  ) {
    /**
     * Creates a StakingManager for the specified competition.
     * This is a helper method to avoid code duplication.
     */
    private func createStakingManager(
      entryStore : CompetitionEntryStore.CompetitionEntryStore
    ) : StakingManager.StakingManager {
      StakingManager.StakingManager(
        entryStore,
        getCirculatingSupply,
        getBackingTokens,
      );
    };

    /**
     * Accept a stake request from a user for the current active competition.
     * This method handles user input validation and returns appropriate errors.
     *
     * @param govStake The governance token stake
     * @param account The account making the stake
     * @param proposedToken The token being proposed
     * @param shouldQueue Whether to queue the submission
     * @return Result with submission details or error
     */
    public func acceptStakeRequest(
      govStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
      shouldQueue : Bool,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount; isQueued : Bool }, Error.CompetitionError> {
      // Get the current active competition
      switch (registryStore.getCurrentCompetitionEntryStore()) {
        case (null) {
          return #err(#CompetitionNotActive);
        };
        case (?entryStore) {
          // Validate the competition is in the right state
          if (entryStore.getStatus() != #AcceptingStakes) {
            return #err(#InvalidPhase({ current = debug_show (entryStore.getStatus()); required = "AcceptingStakes" }));
          };

          // Create the staking manager and process the stake request
          let stakingManager = createStakingManager(entryStore);
          stakingManager.acceptStakeRequest(govStake, account, proposedToken, shouldQueue);
        };
      };
    };

    // TODO: Future methods will be added here:
    // - withdrawRewards() - for distribution phase
    // - comprehensive query methods that return rich data structures
  };
};
