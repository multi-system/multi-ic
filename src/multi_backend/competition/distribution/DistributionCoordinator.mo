import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import EventTypes "../../types/EventTypes";
import CompetitionEntryTypes "../../types/CompetitionEntryTypes";
import SubmissionTypes "../../types/SubmissionTypes";
import StakeTokenTypes "../../types/StakeTokenTypes";
import Error "../../error/Error";
import VirtualAccounts "../../custodial/VirtualAccounts";
import DistributionProcessor "./DistributionProcessor";
import CompetitionEntryStore "../CompetitionEntryStore";

module {
  /// Coordinates the distribution of rewards during competition events
  /// Manages the mapping between positions and accounts, and delegates
  /// the actual distribution calculations to the DistributionProcessor
  public class DistributionCoordinator(
    userAccounts : VirtualAccounts.VirtualAccounts,
    systemAccount : Types.Account,
    stakeTokenConfigs : [StakeTokenTypes.StakeTokenConfig],
  ) {
    private let processor = DistributionProcessor.DistributionProcessor();

    // Extract token list for internal use if needed
    private let stakeTokens = Array.map<StakeTokenTypes.StakeTokenConfig, Types.Token>(
      stakeTokenConfigs,
      func(config) = config.token,
    );

    /// Process a distribution event for a competition
    /// This calculates and distributes rewards based on position performance
    public func processDistribution(
      entryStore : CompetitionEntryStore.CompetitionEntryStore,
      distributionIndex : Nat,
      event : CompetitionEntryTypes.DistributionEvent,
    ) : Result.Result<(), Error.CompetitionError> {

      // Get current positions and submissions from the competition
      let positions = entryStore.getPositions();
      let submissions = entryStore.getAllSubmissions();

      // Retrieve the price event for this distribution
      let priceEventOpt = entryStore.getPriceEventById(event.distributionPrices);

      switch (priceEventOpt) {
        case null {
          return #err(#OperationFailed("Price event not found"));
        };
        case (?priceEvent) {
          // Create mapping function from positions to accounts
          // System positions (no submissionId) return null
          // User positions map through their submission to find the participant
          let getPositionAccount = func(position : RewardTypes.Position) : ?Types.Account {
            switch (position.submissionId) {
              case null { null }; // System position
              case (?submissionId) {
                // Find the submission to get the participant account
                let submissionOpt = Array.find<SubmissionTypes.Submission>(
                  submissions,
                  func(s) = s.id == submissionId,
                );
                switch (submissionOpt) {
                  case null { null };
                  case (?submission) { ?submission.participant };
                };
              };
            };
          };

          // Process the actual distribution
          processor.processDistribution(
            positions,
            priceEvent,
            event.distributionNumber,
            entryStore.getConfig().numberOfDistributionEvents,
            entryStore.getStakeVault(),
            systemAccount,
            getPositionAccount,
            entryStore,
          );

          #ok();
        };
      };
    };
  };
};
