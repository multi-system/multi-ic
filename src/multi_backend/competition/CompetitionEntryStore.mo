import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Int "mo:base/Int";

import Types "../types/Types";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import SubmissionTypes "../types/SubmissionTypes";
import RatioOperations "../financial/RatioOperations";
import SystemStakeTypes "../types/SystemStakeTypes";
import StakeVault "./staking/StakeVault";
import VirtualAccounts "../custodial/VirtualAccounts";
import Error "../error/Error";
import EventTypes "../types/EventTypes";
import RewardTypes "../types/RewardTypes";

module {
  // The CompetitionEntryStore class manages a single competition
  public class CompetitionEntryStore(
    // The competition data - this is passed by reference but any changes need to be saved back
    competitionDataParam : CompetitionEntryTypes.Competition,
    // Callback to persist changes back to the registry
    persistChanges : (CompetitionEntryTypes.Competition) -> (),
    // Shared user accounts used across the system
    userAccounts : VirtualAccounts.VirtualAccounts,
    // The stake vault for this competition
    stakeVault : StakeVault.StakeVault,
  ) {
    // Store competition data in a private field
    private var competitionData : CompetitionEntryTypes.Competition = competitionDataParam;

    // Reference to external method to retrieve price event data
    // Using an optional type for the function
    private var getPriceEventByIdFunc : ?(Nat -> ?EventTypes.PriceEvent) = null;

    // Set the price event retrieval method
    public func setPriceEventRetriever(retriever : (Nat) -> ?EventTypes.PriceEvent) {
      getPriceEventByIdFunc := ?retriever;
    };

    // Update competition status
    public func updateStatus(status : CompetitionEntryTypes.CompetitionStatus) {
      // Add logging to track status changes
      Debug.print(
        "CompetitionEntryStore: Updating competition #" # Nat.toText(competitionData.id) #
        " status from " # debug_show (competitionData.status) #
        " to " # debug_show (status)
      );

      let updated = {
        competitionData with
        status = status;
        completionTime = if (status == #Completed or status == #Distribution) ?Time.now() else competitionData.completionTime;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Update stake rates - rates can only increase
    public func updateStakeRates(govRate : Types.Ratio, multiRate : Types.Ratio) {
      // Verify that gov rate only increases or stays the same
      if (RatioOperations.compare(govRate, competitionData.config.govRate) == #less) {
        Debug.trap("Critical error: Gov stake rate cannot decrease - violates design principle");
      };

      // Verify that multi rate only increases or stays the same
      if (RatioOperations.compare(multiRate, competitionData.config.multiRate) == #less) {
        Debug.trap("Critical error: Multi stake rate cannot decrease - violates design principle");
      };

      let updated = {
        competitionData with
        adjustedGovRate = ?govRate;
        adjustedMultiRate = ?multiRate;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Update total stakes
    public func updateTotalStakes(govStake : Nat, multiStake : Nat) {
      let updated = {
        competitionData with
        totalGovStake = govStake;
        totalMultiStake = multiStake;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Set volume limit
    public func setVolumeLimit(limit : Nat) {
      let updated = {
        competitionData with
        volumeLimit = limit;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Set system stake
    public func setSystemStake(systemStake : SystemStakeTypes.SystemStake) {
      let updated = {
        competitionData with
        systemStake = ?systemStake;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Add a submission to the competition
    public func addSubmission(submission : SubmissionTypes.Submission) {
      // Check for duplicates in array
      for (existing in competitionData.submissions.vals()) {
        if (existing.id == submission.id) {
          Debug.trap("Fatal error: Attempted to add submission with duplicate ID: " # Nat.toText(submission.id));
        };
      };

      // Add to array
      let buffer = Buffer.fromArray<SubmissionTypes.Submission>(competitionData.submissions);
      buffer.add(submission);

      let updated = {
        competitionData with
        submissions = Buffer.toArray(buffer);
        totalGovStake = if (submission.status == #Queued) competitionData.totalGovStake else competitionData.totalGovStake + submission.govStake.value;
        totalMultiStake = if (submission.status == #Queued) competitionData.totalMultiStake else competitionData.totalMultiStake + submission.multiStake.value;
      };
      competitionData := updated;
      persistChanges(updated);
    };

    // Update an existing submission
    public func updateSubmission(submission : SubmissionTypes.Submission) : Bool {
      let buffer = Buffer.fromArray<SubmissionTypes.Submission>(competitionData.submissions);
      var updated = false;

      for (i in Iter.range(0, buffer.size() - 1)) {
        if (buffer.get(i).id == submission.id) {
          buffer.put(i, submission);
          updated := true;
        };
      };

      if (updated) {
        let updatedData = {
          competitionData with
          submissions = Buffer.toArray(buffer);
        };
        competitionData := updatedData;
        persistChanges(updatedData);
      };

      updated;
    };

    // Remove a submission by ID
    public func removeSubmission(id : SubmissionTypes.SubmissionId) : Bool {
      let buffer = Buffer.fromArray<SubmissionTypes.Submission>(competitionData.submissions);
      var indexToRemove : ?Nat = null;
      var removedSubmission : ?SubmissionTypes.Submission = null;

      // Find the submission to remove
      for (i in Iter.range(0, buffer.size() - 1)) {
        let submission = buffer.get(i);
        if (submission.id == id) {
          indexToRemove := ?i;
          removedSubmission := ?submission;
        };
      };

      switch (indexToRemove, removedSubmission) {
        case (null, _) {
          return false;
        };
        case (?index, ?submission) {
          ignore buffer.remove(index);

          let updatedData = {
            competitionData with
            submissions = Buffer.toArray(buffer);
            totalGovStake = if (submission.status == #Queued) competitionData.totalGovStake else competitionData.totalGovStake - submission.govStake.value;
            totalMultiStake = if (submission.status == #Queued) competitionData.totalMultiStake else competitionData.totalMultiStake - submission.multiStake.value;
          };
          competitionData := updatedData;
          persistChanges(updatedData);

          return true;
        };
        case (_, _) {
          Debug.trap("Critical error: Inconsistent state - index found but submission missing");
        };
      };
    };

    // Get submissions by status
    public func getSubmissionsByStatus(status : SubmissionTypes.SubmissionStatus) : [SubmissionTypes.Submission] {
      Array.filter<SubmissionTypes.Submission>(
        competitionData.submissions,
        func(submission) { submission.status == status },
      );
    };

    // Get submission count by status
    public func getSubmissionCountByStatus(status : SubmissionTypes.SubmissionStatus) : Nat {
      Array.size(getSubmissionsByStatus(status));
    };

    // Get a submission by ID
    public func getSubmission(id : SubmissionTypes.SubmissionId) : ?SubmissionTypes.Submission {
      Array.find<SubmissionTypes.Submission>(
        competitionData.submissions,
        func(submission) { submission.id == id },
      );
    };

    // Check if a token is approved in this competition
    public func isTokenApproved(token : Types.Token) : Bool {
      Array.find<Types.Token>(
        competitionData.config.approvedTokens,
        func(t) = Principal.equal(t, token),
      ) != null;
    };

    // Get competition price for a token
    public func getCompetitionPrice(token : Types.Token) : Types.Price {
      let prices = getCompetitionPrices();
      for (price in prices.vals()) {
        if (Principal.equal(price.baseToken, token)) {
          return price;
        };
      };
      Debug.trap("Critical error: No price found for token " # Principal.toText(token) # " in competition " # Nat.toText(competitionData.id));
    };

    // Generate a new submission ID
    public func generateSubmissionId() : SubmissionTypes.SubmissionId {
      let id = competitionData.submissionCounter;

      let updated = {
        competitionData with
        submissionCounter = id + 1;
      };
      competitionData := updated;
      persistChanges(updated);

      id;
    };

    // Calculate volume limit from theta and circulating supply
    public func calculateVolumeLimit(getCirculatingSupply : () -> Nat) : Nat {
      let circulatingSupply = getCirculatingSupply();
      let volumeLimit = RatioOperations.applyToAmount(
        { token = competitionData.config.multiToken; value = circulatingSupply },
        competitionData.config.theta,
      ).value;

      // Update the competition's volume limit
      let updated = {
        competitionData with
        volumeLimit = volumeLimit;
      };
      competitionData := updated;
      persistChanges(updated);

      volumeLimit;
    };

    /**
     * Add a distribution event and update the last distribution index
     *
     * @param distributionEvent The event to add
     */
    public func addDistributionEvent(distributionEvent : CompetitionEntryTypes.DistributionEvent) {
      // Add to events array
      let buffer = Buffer.fromArray<CompetitionEntryTypes.DistributionEvent>(competitionData.distributionHistory);
      buffer.add(distributionEvent);

      // The distribution event already contains the distribution number
      // We should use that as the last distribution index
      let updated = {
        competitionData with
        distributionHistory = Buffer.toArray(buffer);
        lastDistributionIndex = ?distributionEvent.distributionNumber;
      };

      competitionData := updated;
      persistChanges(updated);
    };

    /**
     * Add a position to the competition
     *
     * @param position The position to add
     */
    public func addPosition(position : RewardTypes.Position) {
      let buffer = Buffer.fromArray<RewardTypes.Position>(competitionData.positions);
      buffer.add(position);

      let updated = {
        competitionData with
        positions = Buffer.toArray(buffer);
      };

      competitionData := updated;
      persistChanges(updated);
    };

    /**
     * Get position by submission ID
     *
     * @param submissionId The submission ID to search for
     * @return The position if found
     */
    public func getPositionBySubmissionId(submissionId : SubmissionTypes.SubmissionId) : ?RewardTypes.Position {
      Array.find<RewardTypes.Position>(
        competitionData.positions,
        func(position) {
          switch (position.submissionId) {
            case (?id) { id == submissionId };
            case (null) { false };
          };
        },
      );
    };

    /**
     * Update a position with distribution payout information
     *
     * @param positionIndex Index of the position to update
     * @param distributionNumber The distribution event number
     * @param govPayout Amount of gov tokens paid out
     * @param multiPayout Amount of multi tokens paid out
     * @return True if update successful
     */
    public func updatePositionPayout(
      positionIndex : Nat,
      distributionNumber : Nat,
      govPayout : Nat,
      multiPayout : Nat,
    ) : Bool {
      if (positionIndex < competitionData.positions.size()) {
        let oldPosition = competitionData.positions[positionIndex];

        // Create new payout record
        let newPayout : RewardTypes.DistributionPayout = {
          distributionNumber = distributionNumber;
          govPayout = govPayout;
          multiPayout = multiPayout;
        };

        // Add to existing payouts
        let payoutBuffer = Buffer.fromArray<RewardTypes.DistributionPayout>(oldPosition.distributionPayouts);
        payoutBuffer.add(newPayout);

        // Create updated position
        let updatedPosition = {
          oldPosition with
          distributionPayouts = Buffer.toArray(payoutBuffer);
        };

        // Update the positions array
        let positionsBuffer = Buffer.fromArray<RewardTypes.Position>(competitionData.positions);
        positionsBuffer.put(positionIndex, updatedPosition);

        let updated = {
          competitionData with
          positions = Buffer.toArray(positionsBuffer);
        };

        competitionData := updated;
        persistChanges(updated);
        true;
      } else {
        false;
      };
    };

    /**
     * Get the last distribution index
     *
     * @return The last processed distribution index (null if none)
     */
    public func getLastDistributionIndex() : ?Nat {
      competitionData.lastDistributionIndex;
    };

    /**
     * Get all positions in the competition
     *
     * @return Array of all positions
     */
    public func getPositions() : [RewardTypes.Position] {
      competitionData.positions;
    };

    // === GETTERS ===

    // Get the stake vault for this competition
    public func getStakeVault() : StakeVault.StakeVault {
      stakeVault;
    };

    // Get the competition's ID
    public func getId() : Nat {
      competitionData.id;
    };

    // Get the competition's status
    public func getStatus() : CompetitionEntryTypes.CompetitionStatus {
      competitionData.status;
    };

    // Get competition configuration
    public func getConfig() : CompetitionEntryTypes.CompetitionConfig {
      competitionData.config;
    };

    // Get all submissions
    public func getAllSubmissions() : [SubmissionTypes.Submission] {
      competitionData.submissions;
    };

    // Get total governance stake
    public func getTotalGovStake() : Nat {
      competitionData.totalGovStake;
    };

    // Get total multi stake
    public func getTotalMultiStake() : Nat {
      competitionData.totalMultiStake;
    };

    // Get the governance token
    public func getGovToken() : Types.Token {
      competitionData.config.govToken;
    };

    // Get the multi token
    public func getMultiToken() : Types.Token {
      competitionData.config.multiToken;
    };

    // Get the base governance rate
    public func getGovRate() : Types.Ratio {
      competitionData.config.govRate;
    };

    // Get the adjusted governance rate (if any)
    public func getAdjustedGovRate() : Types.Ratio {
      Option.get(competitionData.adjustedGovRate, competitionData.config.govRate);
    };

    // Get the base multi rate
    public func getMultiRate() : Types.Ratio {
      competitionData.config.multiRate;
    };

    // Get the adjusted multi rate (if any)
    public func getAdjustedMultiRate() : Types.Ratio {
      Option.get(competitionData.adjustedMultiRate, competitionData.config.multiRate);
    };

    // Get approved tokens
    public func getApprovedTokens() : [Types.Token] {
      competitionData.config.approvedTokens;
    };

    // Get competition prices by retrieving from price event
    public func getCompetitionPrices() : [Types.Price] {
      switch (getPriceEventByIdFunc) {
        case (null) {
          Debug.trap("Price event retriever not set - call setPriceEventRetriever first");
        };
        case (?retriever) {
          // Get the price event using the competition's price event ID
          let priceEventOpt = retriever(competitionData.competitionPrices);
          switch (priceEventOpt) {
            case (null) {
              Debug.trap("Critical error: Price event not found for competition " # Nat.toText(competitionData.id) # " with price event ID: " # Nat.toText(competitionData.competitionPrices));
            };
            case (?priceEvent) {
              priceEvent.prices;
            };
          };
        };
      };
    };

    // Get competition price event ID
    public func getCompetitionPriceEventId() : Nat {
      competitionData.competitionPrices;
    };

    // Get volume limit
    public func getVolumeLimit() : Nat {
      competitionData.volumeLimit;
    };

    // Get system stake
    public func getSystemStake() : ?SystemStakeTypes.SystemStake {
      competitionData.systemStake;
    };

    // Get competition data (direct access to the underlying data)
    public func getData() : CompetitionEntryTypes.Competition {
      competitionData;
    };

    // Get a price event by its ID
    public func getPriceEventById(id : Nat) : ?EventTypes.PriceEvent {
      switch (getPriceEventByIdFunc) {
        case (null) {
          Debug.trap("Price event retriever not set - call setPriceEventRetriever first");
        };
        case (?retriever) {
          retriever(id);
        };
      };
    };
  };
};
