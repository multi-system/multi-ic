import Result "mo:base/Result";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import Error "../../error/Error";
import CompetitionEntryTypes "../../types/CompetitionEntryTypes";
import CompetitionEntryStore "../CompetitionEntryStore";
import EventTypes "../../types/EventTypes";
import RewardTypes "../../types/RewardTypes";
import DistributionProcessor "./DistributionProcessor";
import VirtualAccounts "../../custodial/VirtualAccounts";

/**
 * DistributionCoordinator is the main entry point for processing distribution events.
 * It orchestrates the distribution of rewards.
 */
module {
  public class DistributionCoordinator(
    userAccounts : VirtualAccounts.VirtualAccounts,
    systemAccount : Types.Account,
    govToken : Types.Token,
    multiToken : Types.Token,
  ) {
    private let processor = DistributionProcessor.DistributionProcessor(
      govToken,
      multiToken,
    );

    /**
     * Process a distribution event for a competition.
     *
     * @param entryStore The competition entry store
     * @param distributionNumber The distribution event number (0-based)
     * @param distributionEvent The distribution event details
     * @return Result with success or error
     */
    public func processDistribution(
      entryStore : CompetitionEntryStore.CompetitionEntryStore,
      distributionNumber : Nat,
      distributionEvent : CompetitionEntryTypes.DistributionEvent,
    ) : Result.Result<(), Error.CompetitionError> {
      Debug.print("DistributionCoordinator: Processing distribution #" # debug_show (distributionNumber));

      // Get all positions from the competition
      let positions = entryStore.getPositions();
      if (positions.size() == 0) {
        Debug.trap("No positions found during distribution");
      };

      // Get the price event using the ID from distributionEvent
      let priceEventOpt = entryStore.getPriceEventById(distributionEvent.distributionPrices);
      switch (priceEventOpt) {
        case (null) {
          Debug.trap(
            "Price event not found for distribution #" # debug_show (distributionNumber) #
            " with price event ID: " # debug_show (distributionEvent.distributionPrices)
          );
        };
        case (?priceEvent) {
          // Create position-to-account mapping function
          let getPositionAccount = func(position : RewardTypes.Position) : ?Types.Account {
            switch (position.submissionId) {
              case (null) { null }; // System positions handled separately
              case (?subId) {
                switch (entryStore.getSubmission(subId)) {
                  case (null) { null };
                  case (?submission) { ?submission.participant };
                };
              };
            };
          };

          // Process distribution for all positions
          let stakeVault = entryStore.getStakeVault();
          let config = entryStore.getConfig();

          processor.processDistribution(
            positions,
            priceEvent,
            distributionNumber,
            config.numberOfDistributionEvents,
            stakeVault,
            systemAccount,
            getPositionAccount,
            entryStore,
          );

          #ok(());
        };
      };
    };
  };
};
