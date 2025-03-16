import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Option "mo:base/Option";
import SubmissionTypes "../types/SubmissionTypes";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import Types "../types/Types";
import CompetitionTypes "../types/CompetitionTypes";
import RatioOperations "../financial/RatioOperations";

module {
  public class CompetitionStore(state : CompetitionTypes.CompetitionState) {

    // Initialize the competition system with fixed parameters
    public func initialize(
      govToken : Types.Token,
      multiToken : Types.Token,
      initialGovRate : Types.Ratio,
      initialMultiRate : Types.Ratio,
      theta : Types.Ratio,
      systemStakeGov : Types.Ratio,
      systemStakeMulti : Types.Ratio,
      approvedTokens : [Types.Token],
      competitionPrices : [Types.Price],
      competitionPeriodLength : Time.Time,
      competitionSpacing : Time.Time,
      settlementDuration : Time.Time,
      rewardDistributionFrequency : Time.Time,
      numberOfDistributionEvents : Nat,
    ) {
      state.config := {
        govToken;
        multiToken;
        approvedTokens;
        competitionPrices;
        govRate = initialGovRate;
        multiRate = initialMultiRate;
        theta = theta;
        systemStakeGov = systemStakeGov;
        systemStakeMulti = systemStakeMulti;
        competitionPeriodLength = competitionPeriodLength;
        competitionSpacing = competitionSpacing;
        settlementDuration = settlementDuration;
        rewardDistributionFrequency = rewardDistributionFrequency;
        numberOfDistributionEvents = numberOfDistributionEvents;
      };
      state.hasInitialized := true;
      state.competitionActive := false;
      state.submissions := [];
      state.nextSubmissionId := 0;
      state.totalGovStake := 0;
      state.totalMultiStake := 0;
    };

    // Update stake rates with validation that rates can only increase or stay the same
    public func updateStakeRates(govRate : Types.Ratio, multiRate : Types.Ratio) {
      // Verify that gov rate only increases or stays the same
      if (RatioOperations.compare(govRate, state.config.govRate) == #less) {
        Debug.trap("Critical error: Gov stake rate cannot decrease - violates design principle");
      };

      // Verify that multi rate only increases or stays the same
      if (RatioOperations.compare(multiRate, state.config.multiRate) == #less) {
        Debug.trap("Critical error: Multi stake rate cannot decrease - violates design principle");
      };

      // Update the rates
      state.config := {
        state.config with
        govRate = govRate;
        multiRate = multiRate;
      };
    };

    // Update total stakes
    public func updateTotalStakes(govStake : Nat, multiStake : Nat) {
      state.totalGovStake := govStake;
      state.totalMultiStake := multiStake;
    };

    // Set competition active state
    public func setCompetitionActive(active : Bool) {
      state.competitionActive := active;
    };

    // Add a submission to the list
    public func addSubmission(submission : SubmissionTypes.Submission) {
      // Check for duplicates in array
      for (existing in state.submissions.vals()) {
        if (existing.id == submission.id) {
          Debug.trap("Fatal error: Attempted to add submission with duplicate ID: " # Nat.toText(submission.id));
        };
      };

      // Add to array
      let buffer = Buffer.fromArray<SubmissionTypes.Submission>(state.submissions);
      buffer.add(submission);
      state.submissions := Buffer.toArray(buffer);
    };

    // Remove a submission by ID - traps if submission not found
    public func removeSubmission(id : SubmissionTypes.SubmissionId) {
      let buffer = Buffer.fromArray<SubmissionTypes.Submission>(state.submissions);
      var indexToRemove : ?Nat = null;

      // Iterate through indexes
      for (i in Iter.range(0, buffer.size() - 1)) {
        if (buffer.get(i).id == id) {
          indexToRemove := ?i;
        };
      };

      switch (indexToRemove) {
        case (null) {
          Debug.trap("Fatal error: Attempted to remove non-existent submission with ID: " # Nat.toText(id));
        };
        case (?index) {
          ignore buffer.remove(index);
          state.submissions := Buffer.toArray(buffer);
        };
      };
    };

    // Get all submissions with a specific status
    public func getSubmissionsByStatus(status : SubmissionTypes.SubmissionStatus) : [SubmissionTypes.Submission] {
      Array.filter<SubmissionTypes.Submission>(
        state.submissions,
        func(submission) { submission.status == status },
      );
    };

    // Get the number of submissions with a specific status
    public func getSubmissionCountByStatus(status : SubmissionTypes.SubmissionStatus) : Nat {
      Array.size(getSubmissionsByStatus(status));
    };

    // Get submission by ID
    public func getSubmission(id : SubmissionTypes.SubmissionId) : ?SubmissionTypes.Submission {
      Array.find<SubmissionTypes.Submission>(
        state.submissions,
        func(submission) { submission.id == id },
      );
    };

    // Get price for a token
    public func getCompetitionPrice(token : Types.Token) : ?Types.Price {
      for (i in state.config.approvedTokens.keys()) {
        if (Principal.equal(state.config.approvedTokens[i], token)) {
          return ?state.config.competitionPrices[i];
        };
      };
      null;
    };

    // Calculate volume limit on demand from theta and circulating supply
    public func getVolumeLimit(getCirculatingSupply : () -> Nat) : Nat {
      let circulatingSupply = getCirculatingSupply();
      let volumeLimit = RatioOperations.applyToAmount(
        { token = state.config.multiToken; value = circulatingSupply },
        state.config.theta,
      ).value;
      volumeLimit;
    };

    // Get the next submission ID without incrementing it
    public func getNextSubmissionId() : SubmissionTypes.SubmissionId {
      state.nextSubmissionId;
    };

    // Generate a new submission ID (increments the counter)
    public func generateSubmissionId() : SubmissionTypes.SubmissionId {
      let id = state.nextSubmissionId;
      state.nextSubmissionId += 1;
      id;
    };

    // Get all submissions
    public func getAllSubmissions() : [SubmissionTypes.Submission] {
      state.submissions;
    };

    // Query functions
    public func getConfig() : CompetitionTypes.CompetitionConfig {
      state.config;
    };

    public func isTokenApproved(token : Types.Token) : Bool {
      Array.find<Types.Token>(
        state.config.approvedTokens,
        func(t) = Principal.equal(t, token),
      ) != null;
    };

    public func hasInitialized() : Bool { state.hasInitialized };
    public func isCompetitionActive() : Bool { state.competitionActive };
    public func getGovToken() : Types.Token { state.config.govToken };
    public func getMultiToken() : Types.Token { state.config.multiToken };
    public func getGovRate() : Types.Ratio { state.config.govRate };
    public func getMultiRate() : Types.Ratio { state.config.multiRate };
    public func getTheta() : Types.Ratio { state.config.theta };
    public func getSystemStakeGov() : Types.Ratio {
      state.config.systemStakeGov;
    };
    public func getSystemStakeMulti() : Types.Ratio {
      state.config.systemStakeMulti;
    };
    public func getTotalGovStake() : Nat { state.totalGovStake };
    public func getTotalMultiStake() : Nat { state.totalMultiStake };
    public func getApprovedTokens() : [Types.Token] {
      state.config.approvedTokens;
    };
    public func getCompetitionPrices() : [Types.Price] {
      state.config.competitionPrices;
    };
  };
};
