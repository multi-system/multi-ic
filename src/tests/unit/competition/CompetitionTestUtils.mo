import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionTypes "../../../multi_backend/types/CompetitionTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../multi_backend/types/BackingTypes";
import VirtualAccounts "../../../multi_backend/custodial/VirtualAccounts";
import CompetitionStore "../../../multi_backend/competition/CompetitionStore";
import StakeVault "../../../multi_backend/competition/staking/StakeVault";

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

  // Helper function for absolute difference between Nats - useful for comparison with tolerance
  public func natAbsDiff(a : Nat, b : Nat) : Nat {
    if (a > b) { a - b } else { b - a };
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
      govStake = { token = getGovToken(); value = 100 };
      multiStake = { token = getMultiToken(); value = 200 };
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

  // Create a standard competition store with all default settings
  public func createCompetitionStore() : CompetitionStore.CompetitionStore {
    // Create initial state for CompetitionStore
    let state : CompetitionTypes.CompetitionState = {
      var hasInitialized = false;
      var competitionActive = false;
      var config = {
        govToken = getGovToken();
        multiToken = getMultiToken();
        approvedTokens = [];
        competitionPrices = [];
        govRate = { value = getFIVE_PERCENT() };
        multiRate = { value = getONE_PERCENT() };
        theta = { value = getTWENTY_PERCENT() };
        systemStakeGov = { value = getTWENTY_PERCENT() };
        systemStakeMulti = { value = getFIFTY_PERCENT() };
        competitionPeriodLength = 0;
        competitionSpacing = 0;
        settlementDuration = 0;
        rewardDistributionFrequency = 0;
        numberOfDistributionEvents = 0;
      };
      var submissions = [];
      var nextSubmissionId = 0;
      var totalGovStake = 0;
      var totalMultiStake = 0;
    };

    // Create store
    let store = CompetitionStore.CompetitionStore(state);

    // Default time values for test
    let defaultTime : Time.Time = 1_000_000_000_000_000;

    // Create standard prices for test tokens (updated with appropriate values)
    let prices = [
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

    // Initialize the store with standard values
    store.initialize(
      getGovToken(),
      getMultiToken(),
      { value = getFIVE_PERCENT() }, // Initial gov rate: 5%
      { value = getONE_PERCENT() }, // Initial multi rate: 1%
      { value = getTWENTY_PERCENT() }, // Theta: 20%
      { value = getTWENTY_PERCENT() }, // System stake gov: 20%
      { value = getFIFTY_PERCENT() }, // System stake multi: 50%
      [getTestToken1(), getTestToken2(), getTestToken3()],
      prices,
      defaultTime,
      defaultTime,
      defaultTime,
      defaultTime,
      10,
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
    CompetitionStore.CompetitionStore,
    StakeVault.StakeVault,
    Types.Account,
    () -> Nat,
    () -> [BackingTypes.BackingPair],
  ) {
    let store = createCompetitionStore();
    let userAccounts = createUserAccounts();

    // Create stake vault
    let stakeVault = StakeVault.StakeVault(
      userAccounts,
      getMultiToken(),
      getGovToken(),
    );

    // Default circulating supply of 1 million tokens
    let getCirculatingSupply = createCirculatingSupplyFunction(1_000_000);

    // Get backing tokens function
    let getBackingTokens = getBackingTokensFunction();

    (store, stakeVault, getUserPrincipal(), getCirculatingSupply, getBackingTokens);
  };
};
