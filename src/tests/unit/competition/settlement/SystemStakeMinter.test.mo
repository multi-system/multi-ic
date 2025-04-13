import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import { suite; test; expect } "mo:test";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SystemStakeTypes "../../../../multi_backend/types/SystemStakeTypes";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import BackingOperations "../../../../multi_backend/backing/BackingOperations";
import BackingStore "../../../../multi_backend/backing/BackingStore";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import SystemStakeMinter "../../../../multi_backend/competition/settlement/SystemStakeMinter";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "System Stake Minter",
  func() {
    // Setup test environment
    let setupTest = func() : (
      SystemStakeMinter.SystemStakeMinter,
      VirtualAccounts.VirtualAccounts,
      Principal,
    ) {
      // Create virtual accounts
      let userAccounts = CompetitionTestUtils.createUserAccounts();

      // Create backing store
      let backingState : BackingTypes.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 1000; // Supply unit of 1000
          totalSupply = 0;
          backingPairs = [];
          multiToken = CompetitionTestUtils.getMultiToken();
        };
      };

      let backingStore = BackingStore.BackingStore(backingState);
      backingStore.initialize(1000, CompetitionTestUtils.getMultiToken());

      // Create system account
      let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

      // Create backing operations
      let backingOps = BackingOperations.BackingOperations(
        backingStore,
        userAccounts,
        systemAccount,
      );

      // Create system stake minter
      let systemStakeMinter = SystemStakeMinter.SystemStakeMinter(
        userAccounts,
        backingOps,
        backingStore,
        CompetitionTestUtils.getGovToken(),
        systemAccount,
      );

      (systemStakeMinter, userAccounts, systemAccount);
    };

    // Helper to create a test system stake
    let createTestSystemStake = func() : SystemStakeTypes.SystemStake {
      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();

      let govSystemStake : Types.Amount = {
        token = govToken;
        value = 50_000;
      };

      let multiSystemStake : Types.Amount = {
        token = multiToken;
        value = 25_000;
      };

      // Create phantom positions for test tokens
      let token1 = CompetitionTestUtils.getTestToken1();
      let token2 = CompetitionTestUtils.getTestToken2();

      let phantomPos1 : Types.Amount = {
        token = token1;
        value = 10_000;
      };

      let phantomPos2 : Types.Amount = {
        token = token2;
        value = 5_000;
      };

      let phantomPositions : [(Types.Token, Types.Amount)] = [
        (token1, phantomPos1),
        (token2, phantomPos2),
      ];

      {
        govSystemStake;
        multiSystemStake;
        phantomPositions;
      };
    };

    test(
      "mints system stake tokens aligned to supply unit",
      func() {
        let (systemStakeMinter, userAccounts, systemAccount) = setupTest();
        let systemStake = createTestSystemStake();

        let result = systemStakeMinter.mintSystemStake(systemStake);

        // Verify the Multi amount is aligned to supply unit (1000)
        // Original: 25,000 -> aligned should be 25,000 (already divisible)
        assert (result.multiAmount.value == 25_000);
        assert (Principal.equal(result.multiAmount.token, CompetitionTestUtils.getMultiToken()));

        // Verify Gov amount is the same as provided
        assert (result.govAmount.value == 50_000);
        assert (Principal.equal(result.govAmount.token, CompetitionTestUtils.getGovToken()));

        // Verify tokens were minted to the system account
        let systemMultiBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        let systemGovBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken());

        assert (systemMultiBalance.value == 25_000);
        assert (systemGovBalance.value == 50_000);
      },
    );

    test(
      "aligns stake amounts to supply unit",
      func() {
        let (systemStakeMinter, userAccounts, systemAccount) = setupTest();

        // Create a system stake with amounts not divisible by supply unit
        let govToken = CompetitionTestUtils.getGovToken();
        let multiToken = CompetitionTestUtils.getMultiToken();

        let govSystemStake : Types.Amount = {
          token = govToken;
          value = 50_123; // Not divisible by 1000
        };

        let multiSystemStake : Types.Amount = {
          token = multiToken;
          value = 25_499; // Not divisible by 1000
        };

        let systemStake : SystemStakeTypes.SystemStake = {
          govSystemStake;
          multiSystemStake;
          phantomPositions = [];
        };

        let result = systemStakeMinter.mintSystemStake(systemStake);

        // Verify alignment to next higher multiple of supply unit
        // 25,499 should be aligned to 26,000 (next multiple of 1000)
        assert (result.multiAmount.value == 26_000);

        // Gov amount should be unchanged (not subject to alignment)
        assert (result.govAmount.value == 50_123);

        // Verify tokens were minted to system account
        let systemMultiBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        let systemGovBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getGovToken());

        assert (systemMultiBalance.value == 26_000);
        assert (systemGovBalance.value == 50_123);
      },
    );

    test(
      "handles small stake amounts correctly",
      func() {
        let (systemStakeMinter, userAccounts, systemAccount) = setupTest();

        // Create a system stake with a very small multi stake
        let govToken = CompetitionTestUtils.getGovToken();
        let multiToken = CompetitionTestUtils.getMultiToken();

        let govSystemStake : Types.Amount = {
          token = govToken;
          value = 1_000;
        };

        let multiSystemStake : Types.Amount = {
          token = multiToken;
          value = 500; // Less than supply unit
        };

        let systemStake : SystemStakeTypes.SystemStake = {
          govSystemStake;
          multiSystemStake;
          phantomPositions = [];
        };

        let result = systemStakeMinter.mintSystemStake(systemStake);

        // Small value should be aligned up to supply unit
        // 500 should be aligned to 1000 (next multiple of 1000)
        assert (result.multiAmount.value == 1_000);

        // Verify tokens were minted to system account
        let systemMultiBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        assert (systemMultiBalance.value == 1_000);
      },
    );
  },
);
