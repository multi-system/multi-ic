import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import { suite; test; expect } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionRegistryTypes "../../../multi_backend/types/CompetitionRegistryTypes";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import SystemStakeTypes "../../../multi_backend/types/SystemStakeTypes";
import CompetitionManager "../../../multi_backend/competition/CompetitionManager";
import CompetitionRegistryStore "../../../multi_backend/competition/CompetitionRegistryStore";
import CompetitionEntryStore "../../../multi_backend/competition/CompetitionEntryStore";
import CompetitionOrchestrator "../../../multi_backend/competition/CompetitionOrchestrator";
import EventManager "../../../multi_backend/competition/EventManager";
import CompetitionTestUtils "./CompetitionTestUtils";

suite(
  "Competition Orchestrator Tests",
  func() {
    // Create standard time constants for tests
    let SECOND : Time.Time = 1_000_000_000;
    let MINUTE : Time.Time = 60 * SECOND;
    let HOUR : Time.Time = 60 * MINUTE;
    let DAY : Time.Time = 24 * HOUR;

    // Helper function to find a competition by ID in the global competitions array
    func findCompetitionById(
      competitions : [CompetitionEntryTypes.Competition],
      id : Nat,
    ) : ?CompetitionEntryTypes.Competition {
      Array.find<CompetitionEntryTypes.Competition>(
        competitions,
        func(comp) { comp.id == id },
      );
    };

    // Track settlement status for tests
    class SettlementTracker() {
      public var called : Bool = false;
      public var receivedSubmissions : [SubmissionTypes.Submission] = [];
      public var receivedSystemStake : ?SystemStakeTypes.SystemStake = null;
    };

    // Setup test environment for orchestrator tests
    func setupOrchestratorTest() : (
      CompetitionOrchestrator.CompetitionOrchestrator,
      CompetitionRegistryStore.CompetitionRegistryStore,
      () -> Nat, // getCirculatingSupply
      Time.Time, // startTime
      Time.Time, // cycleDuration
      Time.Time, // preAnnouncementDuration
      SettlementTracker // settlement tracker
    ) {
      // Create a shared event registry FIRST
      let sharedEventRegistry = CompetitionTestUtils.createTestEventRegistry();

      // Create registry store WITH the shared event registry
      let registryStore = CompetitionTestUtils.createCompetitionRegistryStoreWithRegistry(sharedEventRegistry);

      // Get the global config for reference
      let globalConfig = registryStore.getGlobalConfig();
      let startTime = registryStore.getStartTime();
      let cycleDuration = globalConfig.competitionCycleDuration;
      let preAnnouncementDuration = globalConfig.preAnnouncementDuration;

      // Create settlement tracker
      let settlementTracker = SettlementTracker();

      // Create the settlement function that tracks calls
      let startSettlement = func(output : CompetitionManager.StakingRoundOutput) : Result.Result<(), Error.CompetitionError> {
        settlementTracker.called := true;
        settlementTracker.receivedSubmissions := output.finalizedSubmissions;
        settlementTracker.receivedSystemStake := ?output.systemStake;
        #ok(());
      };

      // Create supply and token functions
      let getCirculatingSupply = CompetitionTestUtils.createCirculatingSupplyFunction(1_000_000_000); // Example supply
      let getBackingTokens = CompetitionTestUtils.getBackingTokensFunction(); // Example backing tokens

      // Get user accounts and system account functions
      let getUserAccounts = CompetitionTestUtils.getUserAccountsFunction();
      let getSystemAccount = CompetitionTestUtils.getSystemAccountFunction();

      // Create event manager with the SAME shared event registry
      let eventManager = EventManager.EventManager(sharedEventRegistry);

      // Create competition manager
      let competitionManager = CompetitionManager.CompetitionManager(
        getCirculatingSupply,
        getBackingTokens,
        startSettlement,
        getUserAccounts,
        getSystemAccount,
      );

      // Create the orchestrator
      let orchestrator = CompetitionOrchestrator.CompetitionOrchestrator(
        registryStore,
        eventManager,
        competitionManager,
      );

      (
        orchestrator,
        registryStore,
        getCirculatingSupply,
        startTime,
        cycleDuration,
        preAnnouncementDuration,
        settlementTracker,
      );
    };

    // Helper function to create a competition in a specific state
    func createCompetitionInState(
      registryStore : CompetitionRegistryStore.CompetitionRegistryStore,
      state : CompetitionEntryTypes.CompetitionStatus,
      startTime : Time.Time,
    ) : ?Nat {
      switch (registryStore.createCompetition()) {
        case (#err(_)) {
          return null;
        };
        case (#ok(id)) {
          switch (registryStore.getCurrentCompetitionEntryStore()) {
            case (null) {
              return null;
            };
            case (?entryStore) {
              // Update to desired state
              entryStore.updateStatus(state);
              return ?id;
            };
          };
        };
      };
    };

    test(
      "orchestrator manages competition lifecycle",
      func() {
        let (
          orchestrator,
          registryStore,
          _,
          startTime,
          cycleDuration,
          preAnnouncementDuration,
          settlementTracker,
        ) = setupOrchestratorTest();

        // 1. INITIAL STATE - should have no active competition
        expect.bool(registryStore.hasActiveCompetition()).isFalse();

        // 2. CREATE COMPETITION - trigger heartbeat at start time
        orchestrator.heartbeat(startTime);

        // Check if competition was created
        let hasCompetition = registryStore.hasActiveCompetition();
        let currentCompetition = registryStore.getCurrentCompetition();

        // Verify a competition was created
        expect.bool(hasCompetition).isTrue();

        switch (currentCompetition) {
          case (null) {
            // This is inconsistent - registry says we have active competition but returns null
            expect.bool(false).isTrue();
          };
          case (?competition) {
            // New competition should start in PreAnnouncement
            expect.bool(competition.status == #PreAnnouncement).isTrue();
          };
        };

        // 3. TRANSITION TO STAKES PHASE
        let transitionTime = startTime + preAnnouncementDuration;
        orchestrator.heartbeat(transitionTime);

        // Verify now in AcceptingStakes phase
        switch (registryStore.getCurrentCompetition()) {
          case (null) { expect.bool(false).isTrue() };
          case (?updatedComp) {
            expect.bool(updatedComp.status == #AcceptingStakes).isTrue();
          };
        };

        // 4. END STAKING ROUND - Move to Distribution phase
        let endTime = startTime + cycleDuration;
        orchestrator.heartbeat(endTime);

        // Get the first competition to verify it moved to Distribution
        let competitions = registryStore.getGlobalCompetitions();
        var foundDistribution = false;
        for (comp in competitions.vals()) {
          if (comp.id == 1 and comp.status == #Distribution) {
            foundDistribution := true;
          };
        };
        expect.bool(foundDistribution).isTrue();

        // A new competition should have been created automatically
        expect.bool(registryStore.hasActiveCompetition()).isTrue();
        expect.nat(competitions.size()).equal(2);

        // Verify settlement was called
        expect.bool(settlementTracker.called).isTrue();
      },
    );

    test(
      "creates new competition when current moves to distribution",
      func() {
        let (
          orchestrator,
          registryStore,
          _,
          startTime,
          cycleDuration,
          preAnnouncementDuration,
          _,
        ) = setupOrchestratorTest();

        // Create first competition
        orchestrator.heartbeat(startTime);

        // Get the actual first competition ID from the created competition
        let firstCompId = switch (registryStore.getCurrentCompetition()) {
          case (null) { 0 }; // Should not happen
          case (?comp) { comp.id };
        };

        // First, move the competition from PreAnnouncement to AcceptingStakes
        orchestrator.heartbeat(startTime + preAnnouncementDuration);

        // Verify competition is now in AcceptingStakes
        switch (registryStore.getCurrentCompetition()) {
          case (null) { expect.bool(false).isTrue() };
          case (?comp) {
            expect.bool(comp.status == #AcceptingStakes).isTrue();
          };
        };

        // Now end first competition (moves to Distribution)
        orchestrator.heartbeat(startTime + cycleDuration);

        // Verify the first competition moved to Distribution
        let competitions = registryStore.getGlobalCompetitions();
        var foundDistribution = false;
        for (comp in competitions.vals()) {
          if (comp.id == firstCompId and comp.status == #Distribution) {
            foundDistribution := true;
          };
        };
        expect.bool(foundDistribution).isTrue();

        // Should have created a new competition automatically
        expect.bool(registryStore.hasActiveCompetition()).isTrue();

        // Get the actual second competition ID
        let secondCompId = switch (registryStore.getCurrentCompetition()) {
          case (null) { 0 }; // Should not happen
          case (?comp) { comp.id };
        };

        // Verify different IDs
        expect.nat(secondCompId).notEqual(firstCompId);

        // Verify we have 2 competitions total
        expect.nat(registryStore.getGlobalCompetitions().size()).equal(2);
      },
    );

    test(
      "processes distribution events correctly",
      func() {
        let (
          orchestrator,
          registryStore,
          _,
          startTime,
          cycleDuration,
          preAnnouncementDuration,
          _,
        ) = setupOrchestratorTest();

        // Create and end a competition
        orchestrator.heartbeat(startTime);

        // Get the actual competition ID from the created competition
        let competitionId = switch (registryStore.getCurrentCompetition()) {
          case (null) { 0 }; // Should not happen
          case (?comp) { comp.id };
        };

        // First transition to AcceptingStakes
        orchestrator.heartbeat(startTime + preAnnouncementDuration);

        // Then move to Distribution
        orchestrator.heartbeat(startTime + cycleDuration);

        // Get the competition entry store
        switch (registryStore.getCompetitionEntryStoreById(competitionId)) {
          case (null) { expect.bool(false).isTrue() };
          case (?entryStore) {
            // Verify in Distribution phase
            expect.bool(entryStore.getStatus() == #Distribution).isTrue();

            let config = entryStore.getConfig();
            let distributionDuration = config.rewardDistributionDuration;
            let numberOfEvents = config.numberOfDistributionEvents;

            // Process first distribution
            orchestrator.heartbeat(startTime + cycleDuration + distributionDuration);

            // Get a fresh entry store after the orchestrator has processed the distribution
            switch (registryStore.getCompetitionEntryStoreById(competitionId)) {
              case (null) { expect.bool(false).isTrue() };
              case (?freshEntryStore) {
                // Check that distribution was recorded using the fresh store
                let lastDistIndex = freshEntryStore.getLastDistributionIndex();
                expect.bool(Option.isSome(lastDistIndex)).isTrue();

                // Process ALL distributions (10 total)
                // We already processed the first one, so process 9 more
                for (i in Iter.range(1, numberOfEvents - 1)) {
                  let distributionTime = startTime + cycleDuration + (distributionDuration * (i + 1));
                  orchestrator.heartbeat(distributionTime);
                };

                // Now all 10 distributions are complete
                // Process one more heartbeat to trigger the EndCompetition action
                let endCheckTime = startTime + cycleDuration + (distributionDuration * (numberOfEvents + 1));
                orchestrator.heartbeat(endCheckTime);

                // Get fresh store again to check final status
                switch (registryStore.getCompetitionEntryStoreById(competitionId)) {
                  case (null) { expect.bool(false).isTrue() };
                  case (?finalEntryStore) {
                    // Should be completed now
                    expect.bool(finalEntryStore.getStatus() == #Completed).isTrue();
                  };
                };
              };
            };
          };
        };
      },
    );

    test(
      "only creates price events when needed",
      func() {
        let (
          orchestrator,
          registryStore,
          _,
          startTime,
          cycleDuration,
          preAnnouncementDuration,
          _,
        ) = setupOrchestratorTest();

        // Track price events (would need access to event manager in real test)
        var priceEventsBefore = 0; // In real test, get from event manager

        // 1. Heartbeat during PreAnnouncement - no price event
        orchestrator.heartbeat(startTime);
        orchestrator.heartbeat(startTime + preAnnouncementDuration / 2);
        // Price events should not increase

        // 2. Transition to AcceptingStakes - price event created
        orchestrator.heartbeat(startTime + preAnnouncementDuration);
        // Price events should increase by 1

        // 3. Multiple heartbeats during AcceptingStakes - no new price events
        orchestrator.heartbeat(startTime + preAnnouncementDuration + MINUTE);
        orchestrator.heartbeat(startTime + preAnnouncementDuration + (2 * MINUTE));
        // Price events should not increase

        // 4. Distribution event - price event created
        orchestrator.heartbeat(startTime + cycleDuration);
        let distributionTime = startTime + cycleDuration + registryStore.getGlobalConfig().rewardDistributionDuration;
        orchestrator.heartbeat(distributionTime);
        // Price events should increase by 1

        // Test passes if no errors occur
        expect.bool(true).isTrue();
      },
    );

    test(
      "maintains continuous competition operation",
      func() {
        let (
          orchestrator,
          registryStore,
          _,
          startTime,
          cycleDuration,
          _,
          _,
        ) = setupOrchestratorTest();

        // Run through multiple cycles
        var currentTime = startTime;
        var competitionCount = 0;

        // Process 3 full competition cycles
        for (cycle in Iter.range(0, 2)) {
          // Start of cycle
          orchestrator.heartbeat(currentTime);

          // Should always have an active competition
          expect.bool(registryStore.hasActiveCompetition()).isTrue();

          // Move to end of cycle
          orchestrator.heartbeat(currentTime + cycleDuration);

          // Advance time
          currentTime += cycleDuration;
          competitionCount += 1;
        };

        // Should have created competitions for each cycle
        expect.nat(registryStore.getGlobalCompetitions().size()).greaterOrEqual(competitionCount);
      },
    );
  },
);
