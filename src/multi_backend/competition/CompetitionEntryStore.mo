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
import StakeTokenTypes "../types/StakeTokenTypes";
import StakeVault "./staking/StakeVault";
import VirtualAccounts "../custodial/VirtualAccounts";
import Error "../error/Error";
import EventTypes "../types/EventTypes";
import RewardTypes "../types/RewardTypes";
import TokenAccessHelper "../helper/TokenAccessHelper";

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
    private var getPriceEventByIdFunc : ?(Nat -> ?EventTypes.PriceEvent) = null;

    // Set the price event retrieval method
    public func setPriceEventRetriever(retriever : (Nat) -> ?EventTypes.PriceEvent) {
      getPriceEventByIdFunc := ?retriever;
    };

    // Helper to persist competition data changes
    private func persist(updated : CompetitionEntryTypes.Competition) {
      competitionData := updated;
      persistChanges(updated);
    };

    // === STAKE TOKEN HELPER FUNCTIONS ===

    // Get stake token configuration for a specific token
    public func getStakeTokenConfig(token : Types.Token) : ?StakeTokenTypes.StakeTokenConfig {
      Array.find<StakeTokenTypes.StakeTokenConfig>(
        competitionData.config.stakeTokenConfigs,
        func(config) = Principal.equal(config.token, token),
      );
    };

    // Get all stake token configurations
    public func getStakeTokenConfigs() : [StakeTokenTypes.StakeTokenConfig] {
      competitionData.config.stakeTokenConfigs;
    };

    // Check if a token is configured as a stake token
    public func isStakeToken(token : Types.Token) : Bool {
      Option.isSome(getStakeTokenConfig(token));
    };

    // Get all configured stake tokens
    public func getStakeTokens() : [Types.Token] {
      Array.map<StakeTokenTypes.StakeTokenConfig, Types.Token>(
        competitionData.config.stakeTokenConfigs,
        func(config) = config.token,
      );
    };

    // Get base rate for a specific stake token
    public func getBaseRate(token : Types.Token) : Types.Ratio {
      switch (getStakeTokenConfig(token)) {
        case (?config) { config.baseRate };
        case (null) {
          Debug.trap("Token not configured: " # Principal.toText(token));
        };
      };
    };

    // Get system multiplier for a specific stake token
    public func getSystemMultiplier(token : Types.Token) : Types.Ratio {
      switch (getStakeTokenConfig(token)) {
        case (?config) { config.systemMultiplier };
        case (null) {
          Debug.trap("Token not configured: " # Principal.toText(token));
        };
      };
    };

    // Get total stake for a specific token
    public func getTotalStake(token : Types.Token) : Nat {
      TokenAccessHelper.getWithDefault(competitionData.totalStakes, token, 0);
    };

    // Get all total stakes
    public func getAllTotalStakes() : [(Types.Token, Nat)] {
      competitionData.totalStakes;
    };

    // Update total stake for a specific token
    public func updateTotalStake(token : Types.Token, amount : Nat) : Bool {
      persist({
        competitionData with
        totalStakes = TokenAccessHelper.updateInTokenArray(competitionData.totalStakes, token, amount);
      });
      true;
    };

    // Add to total stake for a specific token
    public func addToTotalStake(token : Types.Token, amount : Nat) : Bool {
      updateTotalStake(token, getTotalStake(token) + amount);
    };

    // Subtract from total stake for a specific token
    public func subtractFromTotalStake(token : Types.Token, amount : Nat) : Bool {
      let current = getTotalStake(token);
      if (current >= amount) {
        updateTotalStake(token, current - amount);
      } else {
        false;
      };
    };

    // Get adjusted rate for a specific token
    public func getAdjustedRate(token : Types.Token) : ?Types.Ratio {
      switch (competitionData.adjustedRates) {
        case (null) { null };
        case (?rates) { TokenAccessHelper.findInTokenArray(rates, token) };
      };
    };

    // Get the effective rate for a token (adjusted if exists, otherwise base)
    public func getEffectiveRate(token : Types.Token) : Types.Ratio {
      switch (getAdjustedRate(token)) {
        case (?rate) { rate };
        case (null) { getBaseRate(token) };
      };
    };

    // Update stake rate for a specific token
    public func updateStakeRate(token : Types.Token, newRate : Types.Ratio) : Bool {
      // Verify rate only increases
      let baseRate = getBaseRate(token);
      if (RatioOperations.compare(newRate, baseRate) == #less) {
        Debug.trap("Critical error: Stake rate cannot decrease - violates design principle");
      };

      let adjustedRates = switch (competitionData.adjustedRates) {
        case (null) {
          // First adjustment - initialize with base rates, then update
          let initial = Array.map<StakeTokenTypes.StakeTokenConfig, (Types.Token, Types.Ratio)>(
            competitionData.config.stakeTokenConfigs,
            func(config) = (config.token, config.baseRate),
          );
          TokenAccessHelper.updateInTokenArray(initial, token, newRate);
        };
        case (?rates) {
          TokenAccessHelper.updateInTokenArray(rates, token, newRate);
        };
      };

      persist({
        competitionData with
        adjustedRates = ?adjustedRates;
      });
      true;
    };

    // Update all stake rates at once
    public func updateAllStakeRates(newRates : [(Types.Token, Types.Ratio)]) : Bool {
      // Verify all rates only increase
      for ((token, newRate) in newRates.vals()) {
        let baseRate = getBaseRate(token);
        if (RatioOperations.compare(newRate, baseRate) == #less) {
          Debug.trap("Critical error: Stake rate cannot decrease for token " # Principal.toText(token));
        };
      };

      persist({
        competitionData with
        adjustedRates = ?newRates;
      });
      true;
    };

    // Get stake amount from a submission for a specific token
    public func getSubmissionStake(submission : SubmissionTypes.Submission, token : Types.Token) : ?Types.Amount {
      TokenAccessHelper.findInTokenArray(submission.stakes, token);
    };

    // Get all stakes from a submission
    public func getSubmissionStakes(submission : SubmissionTypes.Submission) : [(Types.Token, Types.Amount)] {
      submission.stakes;
    };

    // Get system stake amount for a specific token
    public func getSystemStakeAmount(token : Types.Token) : Types.Amount {
      switch (competitionData.systemStake) {
        case (null) { { token = token; value = 0 } };
        case (?systemStake) {
          TokenAccessHelper.getWithDefault(
            systemStake.systemStakes,
            token,
            { token = token; value = 0 },
          );
        };
      };
    };

    // === CORE OPERATIONS ===

    // Update competition status
    public func updateStatus(status : CompetitionEntryTypes.CompetitionStatus) {
      Debug.print(
        "CompetitionEntryStore: Updating competition #" # Nat.toText(competitionData.id) #
        " status from " # debug_show (competitionData.status) #
        " to " # debug_show (status)
      );

      persist({
        competitionData with
        status = status;
        completionTime = if (status == #Completed or status == #Distribution) ?Time.now() else competitionData.completionTime;
      });
    };

    // Set volume limit
    public func setVolumeLimit(limit : Nat) {
      persist({ competitionData with volumeLimit = limit });
    };

    // Set system stake
    public func setSystemStake(systemStake : SystemStakeTypes.SystemStake) {
      persist({ competitionData with systemStake = ?systemStake });
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

      // Update total stakes if status is #Staked
      if (submission.status == #Staked) {
        for ((token, amount) in submission.stakes.vals()) {
          ignore addToTotalStake(token, amount.value);
        };
      };

      persist({
        competitionData with
        submissions = Buffer.toArray(buffer);
      });
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
        persist({
          competitionData with
          submissions = Buffer.toArray(buffer);
        });
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
        case (null, _) { false };
        case (?index, ?submission) {
          ignore buffer.remove(index);

          // Subtract from total stakes if status was #Staked
          if (submission.status == #Staked) {
            for ((token, amount) in submission.stakes.vals()) {
              ignore subtractFromTotalStake(token, amount.value);
            };
          };

          persist({
            competitionData with
            submissions = Buffer.toArray(buffer);
          });
          true;
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
      persist({
        competitionData with
        submissionCounter = id + 1;
      });
      id;
    };

    // Calculate volume limit from theta and circulating supply
    public func calculateVolumeLimit(getCirculatingSupply : () -> Nat) : Nat {
      let circulatingSupply = getCirculatingSupply();
      let volumeLimit = RatioOperations.applyToAmount(
        { token = competitionData.config.multiToken; value = circulatingSupply },
        competitionData.config.theta,
      ).value;

      persist({ competitionData with volumeLimit = volumeLimit });
      volumeLimit;
    };

    /**
     * Add a distribution event and update the last distribution index
     */
    public func addDistributionEvent(distributionEvent : CompetitionEntryTypes.DistributionEvent) {
      let buffer = Buffer.fromArray<CompetitionEntryTypes.DistributionEvent>(competitionData.distributionHistory);
      buffer.add(distributionEvent);

      persist({
        competitionData with
        distributionHistory = Buffer.toArray(buffer);
        lastDistributionIndex = ?distributionEvent.distributionNumber;
      });
    };

    /**
     * Add a position to the competition
     */
    public func addPosition(position : RewardTypes.Position) {
      let buffer = Buffer.fromArray<RewardTypes.Position>(competitionData.positions);
      buffer.add(position);

      persist({
        competitionData with
        positions = Buffer.toArray(buffer);
      });
    };

    /**
     * Get position by submission ID
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
     */
    public func updatePositionPayout(
      positionIndex : Nat,
      distributionNumber : Nat,
      payouts : [(Types.Token, Nat)],
    ) : Bool {
      if (positionIndex < competitionData.positions.size()) {
        let oldPosition = competitionData.positions[positionIndex];

        // Create new payout record
        let newPayout : RewardTypes.DistributionPayout = {
          distributionNumber = distributionNumber;
          payouts = payouts;
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

        persist({
          competitionData with
          positions = Buffer.toArray(positionsBuffer);
        });
        true;
      } else {
        false;
      };
    };

    /**
     * Get the last distribution index
     */
    public func getLastDistributionIndex() : ?Nat {
      competitionData.lastDistributionIndex;
    };

    /**
     * Get all positions in the competition
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

    // Get the multi token
    public func getMultiToken() : Types.Token {
      competitionData.config.multiToken;
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
