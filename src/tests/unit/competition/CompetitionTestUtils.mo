import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Hash "mo:base/Hash";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionRegistryTypes "../../../multi_backend/types/CompetitionRegistryTypes";
import EventTypes "../../../multi_backend/types/EventTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import RewardTypes "../../../multi_backend/types/RewardTypes";
import StakeTokenTypes "../../../multi_backend/types/StakeTokenTypes";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import CompetitionEntryStore "../../../multi_backend/competition/CompetitionEntryStore";
import CompetitionRegistryStore "../../../multi_backend/competition/CompetitionRegistryStore";
import StakeVault "../../../multi_backend/competition/staking/StakeVault";
import AccountTypes "../../../multi_backend/types/AccountTypes";

module {
  // Define constants for common percentage values using the same SCALING_FACTOR as in RatioOperations
  public func getSCALING_FACTOR() : Nat { 1_000_000_000 };
  public func getPOINT_ONE_PERCENT() : Nat { 1_000_000 }; // 0.1%
  public func getONE_PERCENT() : Nat { 10_000_000 }; // 1%
  public func getTWO_PERCENT() : Nat { 20_000_000 }; // 2%
  public func getFIVE_PERCENT() : Nat { 50_000_000 }; // 5%
  public func getTEN_PERCENT() : Nat { 100_000_000 }; // 10%
  public func getTWENTY_PERCENT() : Nat { 200_000_000 }; // 20%
  public func getFIFTY_PERCENT() : Nat { 500_000_000 }; // 50%
  public func getONE_HUNDRED_PERCENT() : Nat { 1_000_000_000 }; // 100%

  // Standard token principals for testing
  public func getGovToken() : Types.Token {
    Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
  };

  public func getMultiToken() : Types.Token {
    Principal.fromText("qhbym-qaaaa-aaaaa-aaafq-cai");
  };

  public func getTestToken1() : Types.Token {
    Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
  };

  public func getTestToken2() : Types.Token {
    Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
  };

  public func getTestToken3() : Types.Token {
    Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
  };

  public func getUserPrincipal() : Types.Account {
    Principal.fromText("aaaaa-aa");
  };

  public func getUser2Principal() : Types.Account {
    Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
  };

  public func getSystemPrincipal() : Types.Account {
    // Use a distinct principal for the system
    Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
  };

  // Helper function for absolute difference between Nats - useful for comparison with tolerance
  public func natAbsDiff(a : Nat, b : Nat) : Nat {
    if (a > b) { a - b } else { b - a };
  };

  // Generate a unique test principal from an index
  public func generateTestPrincipal(index : Nat) : Types.Account {
    // Create a unique byte array for each index
    // Principal blobs can be 1-29 bytes
    let bytes = if (index == 0) {
      // Special case: anonymous principal
      [0x04] : [Nat8];
    } else {
      // Create a simple unique byte pattern for each index
      let byte1 = Nat8.fromNat((index / 256) % 256);
      let byte2 = Nat8.fromNat(index % 256);
      [0x01, byte1, byte2] : [Nat8];
    };

    Principal.fromBlob(Blob.fromArray(bytes));
  };

  // Generate valid test principals for testing (alternative method using known valid principals)
  public func getValidTestPrincipal(index : Nat) : Types.Account {
    generateTestPrincipal(index);
  };

  // Create default stake token configurations for testing
  public func createDefaultStakeTokenConfigs() : [StakeTokenTypes.StakeTokenConfig] {
    [
      {
        token = getGovToken();
        baseRate = { value = getFIVE_PERCENT() };
        systemMultiplier = { value = getTWENTY_PERCENT() };
      },
      {
        token = getMultiToken();
        baseRate = { value = getONE_PERCENT() };
        systemMultiplier = { value = getFIFTY_PERCENT() };
      },
    ];
  };

  // Create a test submission for use in tests
  public func createTestSubmission(
    id : SubmissionTypes.SubmissionId,
    account : Types.Account,
    status : SubmissionTypes.SubmissionStatus,
    token : Types.Token,
  ) : SubmissionTypes.Submission {
    {
      id = id;
      participant = account;
      // Stake information
      stakes = [
        (getGovToken(), { token = getGovToken(); value = 100 }),
        (getMultiToken(), { token = getMultiToken(); value = 200 }),
      ];
      // Token information
      token = token;
      // Initial submission
      proposedQuantity = { token = token; value = 1000 };
      timestamp = Time.now();
      // Current state
      status = status;
      rejectionReason = null;
      // Adjustment results
      adjustedQuantity = null;
      // Settlement results
      soldQuantity = null;
      executionPrice = null;
      // Position reference
      positionId = null;
    };
  };

  // Create a test position for use in tests
  public func createTestPosition(
    token : Types.Token,
    quantity : Nat,
    govStake : Nat,
    multiStake : Nat,
    submissionId : ?SubmissionTypes.SubmissionId,
    isSystem : Bool,
  ) : RewardTypes.Position {
    {
      quantity = { token = token; value = quantity };
      stakes = [
        (getGovToken(), { token = getGovToken(); value = govStake }),
        (getMultiToken(), { token = getMultiToken(); value = multiStake }),
      ];
      submissionId = submissionId;
      isSystem = isSystem;
      distributionPayouts = []; // Always starts empty for tests
    };
  };

  // Convenience function for creating a user position from a submission
  public func createUserPositionFromSubmission(
    submission : SubmissionTypes.Submission,
    adjustedQuantity : Types.Amount,
  ) : RewardTypes.Position {
    {
      quantity = adjustedQuantity;
      stakes = submission.stakes;
      submissionId = ?submission.id;
      isSystem = false;
      distributionPayouts = [];
    };
  };

  // Convenience function for creating a system position
  public func createSystemPosition(
    token : Types.Token,
    quantity : Nat,
    govStake : Nat,
    multiStake : Nat,
  ) : RewardTypes.Position {
    createTestPosition(token, quantity, govStake, multiStake, null, true);
  };

  // Create mock backing tokens for testing
  public func createMockBackingTokens() : [BackingTypes.BackingPair] {
    [
      { token = getTestToken1(); backingUnit = 100 },
      { token = getTestToken2(); backingUnit = 200 },
      { token = getTestToken3(); backingUnit = 300 },
    ];
  };

  // Function to get backing tokens for tests
  public func getBackingTokensFunction() : () -> [BackingTypes.BackingPair] {
    func() : [BackingTypes.BackingPair] {
      createMockBackingTokens();
    };
  };

  // Create test prices for use in multiple functions
  public func createTestPrices() : [Types.Price] {
    [
      {
        baseToken = getTestToken1();
        quoteToken = getMultiToken();
        value = { value = getONE_HUNDRED_PERCENT() };
      },
      {
        baseToken = getTestToken2();
        quoteToken = getMultiToken();
        value = { value = getONE_HUNDRED_PERCENT() * 2 };
      },
      {
        baseToken = getTestToken3();
        quoteToken = getMultiToken();
        value = { value = getONE_HUNDRED_PERCENT() * 3 };
      },
    ];
  };

  // Create a mock event registry for testing
  public func createTestEventRegistry() : CompetitionRegistryTypes.EventRegistry {
    // Initialize empty hashmaps for events
    let heartbeats = StableHashMap.init<Nat, EventTypes.HeartbeatEvent>();
    let priceEvents = StableHashMap.init<Nat, EventTypes.PriceEvent>();

    // Create a heartbeat event
    let heartbeatEvent : EventTypes.HeartbeatEvent = {
      id = 1;
      timestamp = Time.now();
    };

    // Create a price event referencing the heartbeat
    let priceEvent : EventTypes.PriceEvent = {
      id = 1;
      heartbeatId = 1;
      prices = createTestPrices();
    };

    // Store events in maps
    StableHashMap.put(heartbeats, Nat.equal, Hash.hash, 1, heartbeatEvent);
    StableHashMap.put(priceEvents, Nat.equal, Hash.hash, 1, priceEvent);

    // Return initialized registry
    {
      var heartbeats = heartbeats;
      var priceEvents = priceEvents;
      var nextHeartbeatId = 2;
      var nextPriceEventId = 2;
      var lastUpdateTime = Time.now();
    };
  };

  // Create a standard competition registry store with default settings
  public func createCompetitionRegistryStore() : CompetitionRegistryStore.CompetitionRegistryStore {
    let eventRegistry = createTestEventRegistry();
    createCompetitionRegistryStoreWithRegistry(eventRegistry);
  };

  // Create a competition registry store with a specific event registry (shared version)
  public func createCompetitionRegistryStoreWithRegistry(
    eventRegistry : CompetitionRegistryTypes.EventRegistry
  ) : CompetitionRegistryStore.CompetitionRegistryStore {
    // Default time values for test
    let defaultTime : Time.Time = 1_000_000_000_000_000;

    // Create initial state with pre-initialized values
    let state : CompetitionRegistryTypes.CompetitionRegistryState = {
      var hasInitialized = true;
      var globalConfig = {
        multiToken = getMultiToken();
        approvedTokens = [getTestToken1(), getTestToken2(), getTestToken3()];
        theta = { value = getTWENTY_PERCENT() };
        stakeTokenConfigs = createDefaultStakeTokenConfigs();
        competitionCycleDuration = defaultTime;
        preAnnouncementDuration = defaultTime / 10; // 10% of cycle is pre-announcement
        rewardDistributionDuration = defaultTime;
        numberOfDistributionEvents = 10;
      };
      var competitions = [];
      var currentCompetitionId = 1;
      var startTime = defaultTime;
      var eventRegistry = eventRegistry;
    };

    // Create user accounts
    let userAccounts = createUserAccounts();

    // Create registry store with pre-initialized state
    CompetitionRegistryStore.CompetitionRegistryStore(state, userAccounts);
  };

  // Create a competition entry for testing
  public func createCompetitionEntry() : CompetitionEntryTypes.Competition {
    // Default time values for test
    let defaultTime : Time.Time = 1_000_000_000_000_000;

    // Configuration for the competition
    let config : CompetitionEntryTypes.CompetitionConfig = {
      multiToken = getMultiToken();
      approvedTokens = [getTestToken1(), getTestToken2(), getTestToken3()];
      theta = { value = getTWENTY_PERCENT() };
      stakeTokenConfigs = createDefaultStakeTokenConfigs();
      competitionCycleDuration = defaultTime;
      preAnnouncementDuration = defaultTime / 10;
      rewardDistributionDuration = defaultTime;
      numberOfDistributionEvents = 10;
    };

    // Initialize empty stake accounts
    let stakeAccounts = StableHashMap.init<Types.Account, AccountTypes.BalanceMap>();

    // Create the competition
    {
      id = 1;
      startTime = Time.now();
      completionTime = null;
      status = #AcceptingStakes;
      config = config;
      competitionPrices = 1; // Reference to test price event with ID 1
      submissions = [];
      submissionCounter = 0;
      totalStakes = [
        (getGovToken(), 0),
        (getMultiToken(), 0),
      ];
      adjustedRates = null;
      volumeLimit = 0;
      systemStake = null;
      stakeAccounts = stakeAccounts;
      lastDistributionIndex = null;
      nextDistributionTime = null;
      distributionHistory = [];
      positions = [];
    };
  };

  // Helper function to get a price event by ID from a test registry
  public func getPriceEventById(registry : CompetitionRegistryTypes.EventRegistry, id : Nat) : ?EventTypes.PriceEvent {
    StableHashMap.get(registry.priceEvents, Nat.equal, Hash.hash, id);
  };

  // Create a competition entry store for testing
  public func createCompetitionEntryStore() : CompetitionEntryStore.CompetitionEntryStore {
    let userAccounts = createUserAccounts();
    let competition = createCompetitionEntry();
    let eventRegistry = createTestEventRegistry();

    let stakeVault = StakeVault.StakeVault(
      userAccounts,
      competition.config.stakeTokenConfigs,
      competition.stakeAccounts,
    );

    let store = CompetitionEntryStore.CompetitionEntryStore(
      competition,
      func(updated : CompetitionEntryTypes.Competition) {
        // No-op persistence for tests
      },
      userAccounts,
      stakeVault,
    );

    // Set the price event retriever function
    store.setPriceEventRetriever(
      func(id : Nat) : ?EventTypes.PriceEvent {
        getPriceEventById(eventRegistry, id);
      }
    );

    store;
  };

  // Create user accounts with standard test balances
  public func createUserAccounts() : VirtualAccounts.VirtualAccounts {
    let userAccounts = VirtualAccounts.VirtualAccounts(
      StableHashMap.init<Types.Account, StableHashMap.StableHashMap<Types.Token, Nat>>()
    );

    // Add test users with standard balances
    userAccounts.mint(getUserPrincipal(), { token = getGovToken(); value = 100_000 });
    userAccounts.mint(getUserPrincipal(), { token = getMultiToken(); value = 50_000 });
    userAccounts.mint(getUserPrincipal(), { token = getTestToken1(); value = 10_000_000 });
    userAccounts.mint(getUserPrincipal(), { token = getTestToken2(); value = 10_000_000 });
    userAccounts.mint(getUserPrincipal(), { token = getTestToken3(); value = 10_000_000 });

    userAccounts.mint(getUser2Principal(), { token = getGovToken(); value = 100_000 });
    userAccounts.mint(getUser2Principal(), { token = getMultiToken(); value = 50_000 });
    userAccounts.mint(getUser2Principal(), { token = getTestToken1(); value = 10_000_000 });
    userAccounts.mint(getUser2Principal(), { token = getTestToken2(); value = 10_000_000 });
    userAccounts.mint(getUser2Principal(), { token = getTestToken3(); value = 10_000_000 });

    userAccounts;
  };

  // Create a standard circulating supply function
  public func createCirculatingSupplyFunction(supply : Nat) : () -> Nat {
    func getCirculatingSupply() : Nat {
      supply;
    };
  };

  // Helper to create a complete test environment with all components
  public func createTestEnvironment() : (
    CompetitionEntryStore.CompetitionEntryStore,
    StakeVault.StakeVault,
    Types.Account,
    () -> Nat,
    () -> [BackingTypes.BackingPair],
    CompetitionRegistryTypes.EventRegistry,
  ) {
    let competitionStore = createCompetitionEntryStore();
    let userAccounts = createUserAccounts();
    let eventRegistry = createTestEventRegistry();

    // Default circulating supply of 1 million tokens
    let getCirculatingSupply = createCirculatingSupplyFunction(1_000_000);

    // Get backing tokens function
    let getBackingTokens = getBackingTokensFunction();

    (competitionStore, competitionStore.getStakeVault(), getUserPrincipal(), getCirculatingSupply, getBackingTokens, eventRegistry);
  };

  // Create a registry state for testing
  public func createCompetitionRegistryState() : CompetitionRegistryTypes.CompetitionRegistryState {
    let defaultTime : Time.Time = 1_000_000_000_000_000;
    let eventRegistry = createTestEventRegistry();

    {
      var hasInitialized = true;
      var globalConfig = {
        multiToken = getMultiToken();
        approvedTokens = [getTestToken1(), getTestToken2(), getTestToken3()];
        theta = { value = getTWENTY_PERCENT() };
        stakeTokenConfigs = createDefaultStakeTokenConfigs();
        competitionCycleDuration = defaultTime;
        preAnnouncementDuration = defaultTime / 10;
        rewardDistributionDuration = defaultTime;
        numberOfDistributionEvents = 10;
      };
      var competitions = [];
      var currentCompetitionId = 1;
      var startTime = defaultTime;
      var eventRegistry = eventRegistry;
    };
  };

  /**
   * Get a function that returns the user accounts instance
   */
  public func getUserAccountsFunction() : () -> VirtualAccounts.VirtualAccounts {
    let userAccounts = createUserAccounts();
    func() : VirtualAccounts.VirtualAccounts {
      userAccounts;
    };
  };

  /**
   * Get a function that returns the system account
   */
  public func getSystemAccountFunction() : () -> Types.Account {
    func() : Types.Account {
      getSystemPrincipal();
    };
  };
};
