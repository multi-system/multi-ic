import Time "mo:base/Time";
import { test } "mo:test";

import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionAutomation "../../../multi_backend/competition/CompetitionAutomation";
import CompetitionStore "../../../multi_backend/competition/CompetitionStore";
import StakeVault "../../../multi_backend/competition/staking/StakeVault";
import StakingManager "../../../multi_backend/competition/staking/StakingManager";
import CompetitionTestUtils "./CompetitionTestUtils";

// Test initialization of configuration
test(
  "CompetitionAutomation - config initialization",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create config for testing
    let testConfig : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000_000; // 1 second
      pauseTime = 500_000_000; // 0.5 seconds
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null, // No settlement initiator for simple test
      testConfig,
    );

    // Verify config was properly set
    let config = automation.getConfig();
    assert (config.activeTime == 1_000_000_000);
    assert (config.pauseTime == 500_000_000);
  },
);

// Test updating configuration
test(
  "CompetitionAutomation - config update",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create initial config
    let initialConfig : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000_000;
      pauseTime = 500_000_000;
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      initialConfig,
    );

    // Update config
    let newConfig : CompetitionAutomation.AutomationConfig = {
      activeTime = 2_000_000_000;
      pauseTime = 1_000_000_000;
    };

    automation.updateConfig(newConfig);

    // Verify config was updated
    let updatedConfig = automation.getConfig();
    assert (updatedConfig.activeTime == 2_000_000_000);
    assert (updatedConfig.pauseTime == 1_000_000_000);
  },
);

// Test state initialization
test(
  "CompetitionAutomation - state initialization",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create config
    let config : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000_000;
      pauseTime = 500_000_000;
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      config,
    );

    // Verify state was properly initialized
    let state = automation.getState();
    assert (state.currentCycleIndex == 0);

    // State should have a reasonable timestamp (within last minute)
    let now = Time.now();
    let timeSinceInit = now - state.lastStateChangeTime;

    // Time difference should be positive but small
    assert (timeSinceInit >= 0);
    assert (timeSinceInit < 60_000_000_000); // Less than 1 minute
  },
);

// Test with minimal values for competition timing
test(
  "CompetitionAutomation - minimal timing values",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create config with minimal values
    let minimalConfig : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000; // 1 millisecond
      pauseTime = 1_000_000; // 1 millisecond
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      minimalConfig,
    );

    // Verify config was properly set with minimal values
    let config = automation.getConfig();
    assert (config.activeTime == 1_000_000);
    assert (config.pauseTime == 1_000_000);
  },
);

// Test with large values for competition timing
test(
  "CompetitionAutomation - large timing values",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create config with large values (30 days in nanoseconds)
    let thirtyDays : Nat = 30 * 24 * 60 * 60 * 1_000_000_000;
    let largeConfig : CompetitionAutomation.AutomationConfig = {
      activeTime = thirtyDays;
      pauseTime = thirtyDays / 10; // 3 days
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      largeConfig,
    );

    // Verify config was properly set with large values
    let config = automation.getConfig();
    assert (config.activeTime == thirtyDays);
    assert (config.pauseTime == thirtyDays / 10);
  },
);

// Test creating a module with a settlement initiator
test(
  "CompetitionAutomation - with settlement initiator",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create a mock settlement initiator
    let mockSettlementInitiator : CompetitionAutomation.SettlementInitiator = func(output) {
      #ok(());
    };

    // Create config
    let config : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000_000;
      pauseTime = 500_000_000;
    };

    // Create automation module with settlement initiator
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      ?mockSettlementInitiator,
      config,
    );

    // Not much to verify here other than it constructs successfully
    assert (true);
  },
);

// Test initial competition state
test(
  "CompetitionAutomation - initial competition state",
  func() {
    // Create test environment
    let (store, stakeVault, _, getCirculatingSupply, getBackingTokens) = CompetitionTestUtils.createTestEnvironment();

    // Set known initial state in store
    store.setCompetitionActive(false);

    // Create StakingManager
    let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Create config
    let config : CompetitionAutomation.AutomationConfig = {
      activeTime = 1_000_000_000;
      pauseTime = 500_000_000;
    };

    // Create automation module
    let automation = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      config,
    );

    // Verify the automation doesn't change the initial competition state
    assert (store.isCompetitionActive() == false);

    // Now test with active state
    store.setCompetitionActive(true);

    // Create another automation module
    let automation2 = CompetitionAutomation.CompetitionAutomation(
      store,
      stakeVault,
      stakingManager,
      getCirculatingSupply,
      getBackingTokens,
      null,
      config,
    );

    // Verify the automation doesn't change the active competition state
    assert (store.isCompetitionActive() == true);
  },
);
