import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionRegistryTypes "../types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import AccountTypes "../types/AccountTypes";
import VirtualAccounts "../custodial/VirtualAccounts";
import StakeVault "./staking/StakeVault";
import CompetitionEntryStore "./CompetitionEntryStore";
import EventTypes "../types/EventTypes";
import Iter "mo:base/Iter";

module {
  public class CompetitionRegistryStore(
    state : CompetitionRegistryTypes.CompetitionRegistryState,
    userAccounts : VirtualAccounts.VirtualAccounts,
  ) {
    // Core operations
    public func createCompetition() : Result.Result<Nat, Error.CompetitionError> {
      if (hasActiveCompetition()) {
        return #err(#InvalidPhase({ current = "active"; required = "inactive" }));
      };

      // Get most recent price event ID for competition prices
      let priceEventIdOpt = getMostRecentPriceEventId();
      switch (priceEventIdOpt) {
        case (null) {
          return #err(#OperationFailed("No price data available"));
        };
        case (?priceEventId) {
          // Create new competition with current ID
          let newId = state.currentCompetitionId;

          // Initialize empty stake accounts
          let stakeAccounts = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();

          // Create new competition using global config
          let newCompetition : CompetitionEntryTypes.Competition = {
            id = newId;
            startTime = Time.now();
            completionTime = null;
            status = #PreAnnouncement;
            config = {
              govToken = state.globalConfig.govToken;
              multiToken = state.globalConfig.multiToken;
              approvedTokens = state.globalConfig.approvedTokens;
              theta = state.globalConfig.theta;
              govRate = state.globalConfig.govRate;
              multiRate = state.globalConfig.multiRate;
              systemStakeGov = state.globalConfig.systemStakeGov;
              systemStakeMulti = state.globalConfig.systemStakeMulti;
              competitionCycleDuration = state.globalConfig.competitionCycleDuration;
              preAnnouncementDuration = state.globalConfig.preAnnouncementDuration;
              rewardDistributionDuration = state.globalConfig.rewardDistributionDuration;
              numberOfDistributionEvents = state.globalConfig.numberOfDistributionEvents;
            };
            competitionPrices = priceEventId;
            submissions = [];
            submissionCounter = 0;
            totalGovStake = 0;
            totalMultiStake = 0;
            adjustedGovRate = null;
            adjustedMultiRate = null;
            volumeLimit = 0;
            systemStake = null;
            stakeAccounts = stakeAccounts;
            lastDistributionIndex = null;
            nextDistributionTime = null;
            distributionHistory = [];
            positions = [];
          };

          // Add to competitions array
          let buffer = Buffer.fromArray<CompetitionEntryTypes.Competition>(state.competitions);
          buffer.add(newCompetition);
          state.competitions := Buffer.toArray(buffer);

          // INCREMENT THE ID FOR NEXT COMPETITION
          state.currentCompetitionId := state.currentCompetitionId + 1;

          #ok(newId);
        };
      };
    };

    // Get the most recent price event ID
    private func getMostRecentPriceEventId() : ?Nat {
      if (state.eventRegistry.nextPriceEventId <= 0) {
        return null;
      };

      let latestId = state.eventRegistry.nextPriceEventId - 1;
      ?latestId;
    };

    // Get a price event by ID
    private func getPriceEventById(id : Nat) : ?EventTypes.PriceEvent {
      StableHashMap.get(
        state.eventRegistry.priceEvents,
        Nat.equal,
        Hash.hash,
        id,
      );
    };

    // State queries
    public func getCurrentCompetition() : ?CompetitionEntryTypes.Competition {
      // Find competition with status that indicates it's active
      Array.find<CompetitionEntryTypes.Competition>(
        state.competitions,
        func(comp) {
          comp.status == #PreAnnouncement or comp.status == #AcceptingStakes or comp.status == #Finalizing or comp.status == #Settlement;
        },
      );
    };

    public func getCurrentCompetitionEntryStore() : ?CompetitionEntryStore.CompetitionEntryStore {
      switch (getCurrentCompetition()) {
        case (null) { null };
        case (?competition) {
          let stakeVault = StakeVault.StakeVault(
            userAccounts,
            competition.config.multiToken,
            competition.config.govToken,
            competition.stakeAccounts,
          );

          let store = CompetitionEntryStore.CompetitionEntryStore(
            competition,
            func(updated : CompetitionEntryTypes.Competition) {
              let updatedWithStakes = {
                updated with
                stakeAccounts = stakeVault.getStakeAccountsMap();
              };
              ignore updateCompetition(updatedWithStakes);
            },
            userAccounts,
            stakeVault,
          );

          // Set the price event retriever function
          store.setPriceEventRetriever(getPriceEventById);

          ?store;
        };
      };
    };

    // Update functions
    public func updateCompetition(competition : CompetitionEntryTypes.Competition) : Bool {
      let buffer = Buffer.fromArray<CompetitionEntryTypes.Competition>(state.competitions);
      var updated = false;

      for (i in Iter.range(0, buffer.size() - 1)) {
        if (buffer.get(i).id == competition.id) {
          buffer.put(i, competition);
          updated := true;
        };
      };

      if (updated) {
        state.competitions := Buffer.toArray(buffer);
      };

      updated;
    };

    public func updateGlobalConfig(newConfig : CompetitionRegistryTypes.GlobalCompetitionConfig) : () {
      state.globalConfig := newConfig;
    };

    // Simple state checks
    public func hasInitialized() : Bool { state.hasInitialized };

    // Check if there is an active competition by verifying the current competition exists
    // and is not in a terminal state (Distribution or Completed)
    public func hasActiveCompetition() : Bool {
      switch (getCurrentCompetition()) {
        case (null) { false };
        case (?comp) {
          comp.status != #Distribution and comp.status != #Completed
        };
      };
    };

    public func getGlobalConfig() : CompetitionRegistryTypes.GlobalCompetitionConfig {
      state.globalConfig;
    };

    public func getCurrentCompetitionId() : Nat {
      state.currentCompetitionId;
    };

    // Token-related checks
    public func isTokenApproved(token : Types.Token) : Bool {
      Array.find<Types.Token>(
        state.globalConfig.approvedTokens,
        func(t) = Principal.equal(t, token),
      ) != null;
    };

    // Get competition price for a token by looking up in the registry's price events
    public func getCompetitionPrice(token : Types.Token) : ?Types.Price {
      // Direct lookup in the price events - for testing
      let priceEvents = getAllPriceEvents();
      if (priceEvents.size() > 0) {
        let priceEvent = priceEvents[0];
        for (price in priceEvent.prices.vals()) {
          if (Principal.equal(price.baseToken, token)) {
            return ?price;
          };
        };
      };

      // Try to look up through competitions if direct lookup failed
      switch (getCurrentCompetition()) {
        case (null) { null };
        case (?competition) {
          let priceEventOpt = getPriceEventById(competition.competitionPrices);

          switch (priceEventOpt) {
            case (null) { null };
            case (?priceEvent) {
              for (price in priceEvent.prices.vals()) {
                if (Principal.equal(price.baseToken, token)) {
                  return ?price;
                };
              };
              null;
            };
          };
        };
      };
    };

    // Gets a CompetitionEntryStore for a specific competition ID.
    public func getCompetitionEntryStoreById(id : Nat) : ?CompetitionEntryStore.CompetitionEntryStore {
      // Find the competition with the specified ID
      let competitionOpt = Array.find<CompetitionEntryTypes.Competition>(
        state.competitions,
        func(comp) { comp.id == id },
      );

      switch (competitionOpt) {
        case (null) { null };
        case (?competition) {
          // Create a StakeVault for this competition
          let stakeVault = StakeVault.StakeVault(
            userAccounts,
            competition.config.multiToken,
            competition.config.govToken,
            competition.stakeAccounts,
          );

          // Create and return a new CompetitionEntryStore
          let store = CompetitionEntryStore.CompetitionEntryStore(
            competition,
            func(updated : CompetitionEntryTypes.Competition) {
              let updatedWithStakes = {
                updated with
                stakeAccounts = stakeVault.getStakeAccountsMap();
              };
              ignore updateCompetition(updatedWithStakes);
            },
            userAccounts,
            stakeVault,
          );

          // Set the price event retriever function
          store.setPriceEventRetriever(getPriceEventById);

          ?store;
        };
      };
    };

    public func getGlobalCompetitions() : [CompetitionEntryTypes.Competition] {
      state.competitions;
    };

    public func getStartTime() : Time.Time {
      state.startTime;
    };

    // Added helper functions for working with event registry
    public func getHeartbeatById(id : Nat) : ?EventTypes.HeartbeatEvent {
      StableHashMap.get(
        state.eventRegistry.heartbeats,
        Nat.equal,
        Hash.hash,
        id,
      );
    };

    public func getAllHeartbeats() : [EventTypes.HeartbeatEvent] {
      let buffer = Buffer.Buffer<EventTypes.HeartbeatEvent>(0);
      for ((_, heartbeat) in StableHashMap.entries(state.eventRegistry.heartbeats)) {
        buffer.add(heartbeat);
      };
      Buffer.toArray(buffer);
    };

    public func getAllPriceEvents() : [EventTypes.PriceEvent] {
      let buffer = Buffer.Buffer<EventTypes.PriceEvent>(0);
      for ((_, priceEvent) in StableHashMap.entries(state.eventRegistry.priceEvents)) {
        buffer.add(priceEvent);
      };
      Buffer.toArray(buffer);
    };
  };
};
