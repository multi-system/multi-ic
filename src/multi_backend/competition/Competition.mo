import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";

module {
  public let PRICE_DECIMALS : Nat = 8;
  public let PRICE_SCALE : Nat = 100_000_000; // 10^8
  public let BASIS_POINTS_SCALE : Nat = 10_000; // For markup: 100% = 10000
  public let NANOS_PER_SECOND : Nat = 1_000_000_000;

  public type TokenPrice = {
    token : Principal;
    oraclePrice : Nat; // Price * 10^8
    timestamp : Time.Time;
  };

  // System parameters set by DAO
  public type SystemParameters = {
    maxVolume : Nat; // Max volume ratio in basis points
    minGovStake : Nat; // Required governance token stake
    minMultiStake : Nat; // Required Multi token stake
    competitionDuration : Nat; // Duration in seconds
    settlementDuration : Nat; // Settlement in seconds
    distributionPeriod : Nat; // Distribution period in seconds
    numDistributions : Nat; // Number of distributions
    markup : Nat; // Price markup in basis points
  };

  // Competition-specific settings (immutable once created)
  public type Competition = {
    id : Nat;
    maxVolume : Nat; // From system parameters at creation
    minGovStake : Nat; // From system parameters at creation
    minMultiStake : Nat; // From system parameters at creation
    startTime : Time.Time; // When competition starts
    duration : Nat; // From system parameters at creation
    settlementDuration : Nat; // From system parameters at creation
    distributionPeriod : Nat; // From system parameters at creation
    numDistributions : Nat; // From system parameters at creation
    markup : Nat; // From system parameters at creation
    approvedTokens : [TokenPrice];
    created : Time.Time;
  };

  public type State = {
    #NotStarted;
    #Submission; // Users can submit stakes and tokens
    #Settlement;
    #Distribution;
    #Completed;
  };

  public class CompetitionManager(owner : Principal) {
    private var nextId : Nat = 0;
    private let competitions = HashMap.HashMap<Nat, Competition>(10, Nat.equal, Hash.hash);

    // Current system parameters
    private var parameters : SystemParameters = {
      maxVolume = 1_000; // 10%
      minGovStake = 100_000 * PRICE_SCALE;
      minMultiStake = 50_000 * PRICE_SCALE;
      competitionDuration = 3600; // 1 hour
      settlementDuration = 1800; // 30 minutes
      distributionPeriod = 86400; // 24 hours
      numDistributions = 24; // Every hour
      markup = 500; // 5%
    };

    public func updateParameters(
      caller : Principal,
      newParams : SystemParameters,
    ) : Result.Result<(), Text> {
      if (caller != owner) {
        return #err("Unauthorized");
      };

      if (newParams.maxVolume > BASIS_POINTS_SCALE) {
        return #err("Max volume cannot exceed 100%");
      };

      if (newParams.markup > BASIS_POINTS_SCALE) {
        return #err("Markup cannot exceed 100%");
      };

      parameters := newParams;
      #ok();
    };

    public func getParameters() : SystemParameters {
      parameters;
    };

    // Create new competition using current system parameters
    public func createCompetition(
      caller : Principal,
      startTime : Time.Time,
      prices : [TokenPrice],
    ) : Result.Result<Nat, Text> {
      if (caller != owner) {
        return #err("Unauthorized");
      };

      // Competition must be scheduled to start in the future
      if (startTime <= Time.now()) {
        return #err("Competition must start in the future");
      };

      for (price in prices.vals()) {
        if (price.oraclePrice == 0) {
          return #err("Oracle price cannot be zero");
        };
      };

      let competition : Competition = {
        id = nextId;
        maxVolume = parameters.maxVolume;
        minGovStake = parameters.minGovStake;
        minMultiStake = parameters.minMultiStake;
        startTime = startTime;
        duration = parameters.competitionDuration;
        settlementDuration = parameters.settlementDuration;
        distributionPeriod = parameters.distributionPeriod;
        numDistributions = parameters.numDistributions;
        markup = parameters.markup;
        approvedTokens = prices;
        created = Time.now();
      };

      competitions.put(nextId, competition);
      nextId += 1;

      #ok(competition.id);
    };

    public func getCompetition(id : Nat) : ?Competition {
      competitions.get(id);
    };

    // Returns the current competition state based on time
    public func getCompetitionState(id : Nat) : ?State {
      switch (competitions.get(id)) {
        case null null;
        case (?competition) {
          ?determineCompetitionState(competition);
        };
      };
    };

    public func isInSubmissionPhase(id : Nat) : Bool {
      switch (getCompetitionState(id)) {
        case (? #Submission) true;
        case _ false;
      };
    };

    public func getCompetitionPrice(id : Nat, token : Principal) : ?Nat {
      switch (competitions.get(id)) {
        case (null) null;
        case (?competition) {
          // Only return prices if competition is active
          if (determineCompetitionState(competition) != #Submission) {
            return null;
          };

          for (price in competition.approvedTokens.vals()) {
            if (Principal.equal(price.token, token)) {
              let numerator = price.oraclePrice * (BASIS_POINTS_SCALE + competition.markup);
              return ?(numerator / BASIS_POINTS_SCALE);
            };
          };
          null;
        };
      };
    };

    private func determineCompetitionState(competition : Competition) : State {
      let now = Time.now();
      let start = competition.startTime;
      let end = start + (competition.duration * NANOS_PER_SECOND);
      let settlementEnd = end + (competition.settlementDuration * NANOS_PER_SECOND);
      let distributionEnd = settlementEnd + (competition.distributionPeriod * NANOS_PER_SECOND);

      if (now < start) {
        #NotStarted;
      } else if (now < end) {
        #Submission;
      } else if (now < settlementEnd) {
        #Settlement;
      } else if (now < distributionEnd) {
        #Distribution;
      } else {
        #Completed;
      };
    };
  };
};
