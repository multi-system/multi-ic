import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../types/Types";
import Error "../error/Error";
import CompetitionRegistryTypes "../types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import AccountTypes "../types/AccountTypes";
import VirtualAccounts "../custodial/VirtualAccounts";
import StakeVault "./staking/StakeVault";
import CompetitionEntryStore "./CompetitionEntryStore";
import Iter "mo:base/Iter";

module {
  public class CompetitionRegistryStore(
    state : CompetitionRegistryTypes.RegistryState,
    userAccounts : VirtualAccounts.VirtualAccounts,
  ) {
    // Core operations
    public func createCompetition() : Result.Result<Nat, Error.CompetitionError> {
      if (state.currentCompetitionId != null) {
        return #err(#InvalidPhase({ current = "active"; required = "inactive" }));
      };

      // Create new competition with next ID
      let newId = state.nextCompetitionId;
      state.nextCompetitionId += 1;

      // Initialize empty stake accounts
      let stakeAccounts = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();

      // Create new competition entry using global config
      let newCompetition : CompetitionEntryTypes.CompetitionEntry = {
        id = newId;
        startTime = Time.now();
        endTime = null;
        status = #PreAnnouncement;
        config = {
          govToken = state.globalConfig.govToken;
          multiToken = state.globalConfig.multiToken;
          approvedTokens = state.globalConfig.approvedTokens;
          competitionPrices = state.globalConfig.competitionPrices;
          theta = state.globalConfig.theta;
          govRate = state.globalConfig.govRate;
          multiRate = state.globalConfig.multiRate;
          systemStakeGov = state.globalConfig.systemStakeGov;
          systemStakeMulti = state.globalConfig.systemStakeMulti;
          competitionCycleDuration = state.globalConfig.competitionCycleDuration;
          preAnnouncementPeriod = state.globalConfig.preAnnouncementPeriod;
          rewardDistributionFrequency = state.globalConfig.rewardDistributionFrequency;
          numberOfDistributionEvents = state.globalConfig.numberOfDistributionEvents;
        };
        submissions = [];
        nextSubmissionId = 0;
        totalGovStake = 0;
        totalMultiStake = 0;
        adjustedGovRate = null;
        adjustedMultiRate = null;
        volumeLimit = 0;
        systemStake = null;
        stakeAccounts = stakeAccounts;
      };

      // Add to competitions array and set as current
      let buffer = Buffer.fromArray<CompetitionEntryTypes.CompetitionEntry>(state.competitions);
      buffer.add(newCompetition);
      state.competitions := Buffer.toArray(buffer);
      state.currentCompetitionId := ?newId;

      #ok(newId);
    };

    // State queries
    public func getCurrentCompetition() : ?CompetitionEntryTypes.CompetitionEntry {
      switch (state.currentCompetitionId) {
        case (null) { null };
        case (?id) {
          Array.find<CompetitionEntryTypes.CompetitionEntry>(
            state.competitions,
            func(comp) { comp.id == id },
          );
        };
      };
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

          ?CompetitionEntryStore.CompetitionEntryStore(
            competition,
            func(updated : CompetitionEntryTypes.CompetitionEntry) {
              let updatedWithStakes = {
                updated with
                stakeAccounts = stakeVault.getStakeAccountsMap();
              };
              ignore updateCompetition(updatedWithStakes);
            },
            userAccounts,
            stakeVault,
          );
        };
      };
    };

    // Update functions
    public func updateCompetition(competition : CompetitionEntryTypes.CompetitionEntry) : Bool {
      let buffer = Buffer.fromArray<CompetitionEntryTypes.CompetitionEntry>(state.competitions);
      var updated = false;

      for (i in Iter.range(0, buffer.size() - 1)) {
        if (buffer.get(i).id == competition.id) {
          buffer.put(i, competition);
          updated := true;

          // If setting to completed or distribution, clear current competition ID if it matches
          if ((competition.status == #Completed or competition.status == #Distribution) and state.currentCompetitionId == ?competition.id) {
            state.currentCompetitionId := null;
          };
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
    public func hasActiveCompetition() : Bool {
      state.currentCompetitionId != null;
    };
    public func getGlobalConfig() : CompetitionRegistryTypes.GlobalCompetitionConfig {
      state.globalConfig;
    };
    public func getCurrentCompetitionId() : ?Nat { state.currentCompetitionId };

    // Token-related checks
    public func isTokenApproved(token : Types.Token) : Bool {
      Array.find<Types.Token>(
        state.globalConfig.approvedTokens,
        func(t) = Principal.equal(t, token),
      ) != null;
    };

    public func getCompetitionPrice(token : Types.Token) : ?Types.Price {
      for (i in Iter.range(0, state.globalConfig.approvedTokens.size() - 1)) {
        if (Principal.equal(state.globalConfig.approvedTokens[i], token)) {
          return ?state.globalConfig.competitionPrices[i];
        };
      };
      null;
    };

    //  Gets a CompetitionEntryStore for a specific competition ID.
    public func getCompetitionEntryStoreById(id : Nat) : ?CompetitionEntryStore.CompetitionEntryStore {
      // Find the competition with the specified ID
      let competitionOpt = Array.find<CompetitionEntryTypes.CompetitionEntry>(
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
          ?CompetitionEntryStore.CompetitionEntryStore(
            competition,
            func(updated : CompetitionEntryTypes.CompetitionEntry) {
              let updatedWithStakes = {
                updated with
                stakeAccounts = stakeVault.getStakeAccountsMap();
              };
              ignore updateCompetition(updatedWithStakes);
            },
            userAccounts,
            stakeVault,
          );
        };
      };
    };

    public func getGlobalCompetitions() : [CompetitionEntryTypes.CompetitionEntry] {
      state.competitions;
    };

    public func getEpochStartTime() : Time.Time {
      state.epochStartTime;
    };

  };
};
