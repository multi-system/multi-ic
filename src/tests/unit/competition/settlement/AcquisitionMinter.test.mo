import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Map "mo:base/HashMap";
import Text "mo:base/Text";
import Array "mo:base/Array";
import { suite; test; expect } "mo:test";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import BackingTypes "../../../../multi_backend/types/BackingTypes";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import BackingOperations "../../../../multi_backend/backing/BackingOperations";
import BackingStore "../../../../multi_backend/backing/BackingStore";
import AcquisitionMinter "../../../../multi_backend/competition/settlement/AcquisitionMinter";
import CompetitionTestUtils "../CompetitionTestUtils";

suite(
  "Acquisition Minter",
  func() {
    // Setup test environment
    let setupTest = func() : (
      AcquisitionMinter.AcquisitionMinter,
      VirtualAccounts.VirtualAccounts,
      Principal,
      BackingStore.BackingStore,
      Map.HashMap<Text, Types.Price>,
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

      // Add backing tokens
      backingStore.updateBackingTokens([
        {
          token = CompetitionTestUtils.getTestToken1();
          backingUnit = 10;
        },
        {
          token = CompetitionTestUtils.getTestToken2();
          backingUnit = 20;
        },
      ]);

      // Create system account with valid Principal
      let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

      // Create backing operations
      let backingOps = BackingOperations.BackingOperations(
        backingStore,
        userAccounts,
        systemAccount,
      );

      // Create acquisition minter
      let acquisitionMinter = AcquisitionMinter.AcquisitionMinter(
        userAccounts,
        backingOps,
        backingStore,
        systemAccount,
      );

      // Create price map
      let priceMap = Map.HashMap<Text, Types.Price>(10, Text.equal, Text.hash);

      // Add prices for test tokens
      priceMap.put(
        Principal.toText(CompetitionTestUtils.getTestToken1()),
        {
          baseToken = CompetitionTestUtils.getTestToken1();
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
          }; // 1.0 ratio
        },
      );

      priceMap.put(
        Principal.toText(CompetitionTestUtils.getTestToken2()),
        {
          baseToken = CompetitionTestUtils.getTestToken2();
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
          }; // 2.0 ratio
        },
      );

      (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap);
    };

    // Helper to create finalized submissions
    let createFinalizedSubmissions = func(
      withTokens : [Types.Token],
      withQuantities : [Nat],
    ) : [SubmissionTypes.Submission] {
      let testUser = CompetitionTestUtils.getUserPrincipal();
      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();

      // Create submissions for each token and quantity
      let submissions = Array.tabulate<SubmissionTypes.Submission>(
        withTokens.size(),
        func(index : Nat) : SubmissionTypes.Submission {
          let token = withTokens[index];
          let quantity = withQuantities[index];

          // Create stakes array for this submission
          let stakes : [(Types.Token, Types.Amount)] = [
            (govToken, { token = govToken; value = 1000 * (index + 1) }),
            (multiToken, { token = multiToken; value = 200 * (index + 1) }),
          ];

          // Create adjusted quantity
          let adjustedQuantity : Types.Amount = {
            token = token;
            value = quantity;
          };

          {
            id = index;
            participant = testUser;
            stakes = stakes;
            token = token;
            proposedQuantity = adjustedQuantity;
            timestamp = 0;
            status = #Finalized;
            rejectionReason = null;
            adjustedQuantity = ?adjustedQuantity;
            soldQuantity = null;
            executionPrice = null;
            positionId = null;
          };
        },
      );

      submissions;
    };

    test(
      "calculates multi values correctly for multiple submissions",
      func() {
        let (acquisitionMinter, _, _, _, priceMap) = setupTest();

        // Create submissions with different tokens and quantities
        let token1 = CompetitionTestUtils.getTestToken1(); // Price 1.0
        let token2 = CompetitionTestUtils.getTestToken2(); // Price 2.0

        let submissions = createFinalizedSubmissions(
          [token1, token2],
          [10_000, 5_000],
        );

        // Calculate multi values
        let result = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Expected values:
        // Submission 0: 10,000 of token1 at price 1.0 = 10,000 Multi value
        // Submission 1: 5,000 of token2 at price 2.0 = 10,000 Multi value
        // Total: 20,000 Multi value

        // Verify total value
        expect.nat(result.totalMultiValue).equal(20_000);

        // Verify per-submission values
        expect.nat(result.submissionValues.size()).equal(2);

        // Submission IDs and values should match expectations
        expect.nat(result.submissionValues[0].0).equal(0); // Submission ID
        expect.nat(result.submissionValues[0].1).equal(10_000); // Value

        expect.nat(result.submissionValues[1].0).equal(1); // Submission ID
        expect.nat(result.submissionValues[1].1).equal(10_000); // Value
      },
    );

    test(
      "aligns mint amount to supply unit",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create submissions with values that won't align perfectly to supply unit
        let token1 = CompetitionTestUtils.getTestToken1(); // Price 1.0
        let token2 = CompetitionTestUtils.getTestToken2(); // Price 2.0

        // This will result in a total raw value of 9,900 + 10,200 = 20,100
        // which should be aligned up to 21,000 (next multiple of 1000)
        let submissions = createFinalizedSubmissions(
          [token1, token2],
          [9_900, 5_100],
        );

        // Get supply unit
        let supplyUnit = backingStore.getSupplyUnit();
        expect.nat(supplyUnit).equal(1000);

        // Initial supply
        let initialSupply = backingStore.getTotalSupply().value;

        // Mint tokens
        let result = acquisitionMinter.mintAcquisitionTokens(
          submissions,
          priceMap,
        );

        // Expected raw values:
        // Submission 0: 9,900 of token1 at price 1.0 = 9,900 Multi value
        // Submission 1: 5,100 of token2 at price 2.0 = 10,200 Multi value
        // Total raw: 20,100 Multi value
        // Aligned to supply unit (1000): 21,000

        // Verify minted amount is properly aligned
        expect.nat(result.mintedAmount.value).equal(21_000);
        expect.principal(result.mintedAmount.token).equal(CompetitionTestUtils.getMultiToken());

        // Verify per-submission values (raw, not aligned)
        expect.nat(result.submissionValues.size()).equal(2);
        expect.nat(result.submissionValues[0].1).equal(9_900);
        expect.nat(result.submissionValues[1].1).equal(10_200);

        // Verify backing store total supply increased
        expect.nat(backingStore.getTotalSupply().value).equal(initialSupply + 21_000);

        // Verify system account balance increased
        let systemBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        expect.nat(systemBalance.value).equal(21_000);
      },
    );

    test(
      "handles zero quantity submissions",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create submissions with zero quantities
        let token1 = CompetitionTestUtils.getTestToken1();
        let token2 = CompetitionTestUtils.getTestToken2();

        let submissions = createFinalizedSubmissions(
          [token1, token2],
          [0, 0],
        );

        // Calculate multi values - this should work fine with zeros
        let calculationResult = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Verify zero values
        expect.nat(calculationResult.totalMultiValue).equal(0);
        expect.nat(calculationResult.submissionValues.size()).equal(2);
        expect.nat(calculationResult.submissionValues[0].1).equal(0);
        expect.nat(calculationResult.submissionValues[1].1).equal(0);
      },
    );

    test(
      "handles empty submissions array",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Empty submissions array
        let submissions : [SubmissionTypes.Submission] = [];

        // Calculate multi values
        let calculationResult = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Verify empty results
        expect.nat(calculationResult.totalMultiValue).equal(0);
        expect.nat(calculationResult.submissionValues.size()).equal(0);
      },
    );

    test(
      "handles small values below supply unit",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create submission with small value below supply unit (1000)
        let token1 = CompetitionTestUtils.getTestToken1(); // Price 1.0

        let submissions = createFinalizedSubmissions(
          [token1],
          [500] // Will produce 500 Multi value, below supply unit
        );

        // Initial supply
        let initialSupply = backingStore.getTotalSupply().value;

        // Calculate multi values
        let calculationResult = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Verify raw value
        expect.nat(calculationResult.totalMultiValue).equal(500);

        // Mint tokens
        let mintResult = acquisitionMinter.mintAcquisitionTokens(
          submissions,
          priceMap,
        );

        // Verify minted amount is aligned to supply unit (500 -> 1000)
        expect.nat(mintResult.mintedAmount.value).equal(1000);

        // Verify backing store total supply increased by aligned amount
        expect.nat(backingStore.getTotalSupply().value).equal(initialSupply + 1000);

        // Verify system account balance increased by aligned amount
        let systemBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        expect.nat(systemBalance.value).equal(1000);
      },
    );

    test(
      "handles value exactly equal to supply unit",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create submission with value exactly equal to supply unit (1000)
        let token1 = CompetitionTestUtils.getTestToken1(); // Price 1.0

        let submissions = createFinalizedSubmissions(
          [token1],
          [1000] // Will produce 1000 Multi value, equal to supply unit
        );

        // Initial supply
        let initialSupply = backingStore.getTotalSupply().value;

        // Mint tokens
        let mintResult = acquisitionMinter.mintAcquisitionTokens(
          submissions,
          priceMap,
        );

        // Verify minted amount is same as supply unit
        expect.nat(mintResult.mintedAmount.value).equal(1000);

        // Verify backing store total supply increased by exactly supply unit
        expect.nat(backingStore.getTotalSupply().value).equal(initialSupply + 1000);
      },
    );

    test(
      "handles large values",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create submission with large value
        let token1 = CompetitionTestUtils.getTestToken1(); // Price 1.0
        let token2 = CompetitionTestUtils.getTestToken2(); // Price 2.0

        let submissions = createFinalizedSubmissions(
          [token1, token2],
          [1_000_000, 2_000_000] // Will produce 5,000,000 Multi value
        );

        // Initial supply
        let initialSupply = backingStore.getTotalSupply().value;

        // Calculate multi values
        let calculationResult = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Expected values:
        // Submission 0: 1,000,000 of token1 at price 1.0 = 1,000,000 Multi value
        // Submission 1: 2,000,000 of token2 at price 2.0 = 4,000,000 Multi value
        // Total: 5,000,000 Multi value

        // Verify raw values
        expect.nat(calculationResult.totalMultiValue).equal(5_000_000);
        expect.nat(calculationResult.submissionValues[0].1).equal(1_000_000);
        expect.nat(calculationResult.submissionValues[1].1).equal(4_000_000);

        // Mint tokens
        let mintResult = acquisitionMinter.mintAcquisitionTokens(
          submissions,
          priceMap,
        );

        // Verify minted amount (5,000,000 is already aligned to supply unit)
        expect.nat(mintResult.mintedAmount.value).equal(5_000_000);

        // Verify backing store total supply increased
        expect.nat(backingStore.getTotalSupply().value).equal(initialSupply + 5_000_000);

        // Verify system account balance increased
        let systemBalance = userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken());
        expect.nat(systemBalance.value).equal(5_000_000);
      },
    );

    test(
      "handles non-standard price values",
      func() {
        let (acquisitionMinter, userAccounts, systemAccount, backingStore, priceMap) = setupTest();

        // Create a price with a non-standard ratio (1.5)
        let token1 = CompetitionTestUtils.getTestToken1();
        let nonStandardPrice : Types.Price = {
          baseToken = token1;
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 3 / 2;
          }; // 1.5 ratio
        };

        // Add this price to the price map
        priceMap.put(Principal.toText(token1), nonStandardPrice);

        // Create submission with quantity 1000, which with price 1.5 should yield value 1500
        let submissions = createFinalizedSubmissions(
          [token1],
          [1000],
        );

        // Calculate multi values
        let result = acquisitionMinter.calculateMultiValues(
          submissions,
          priceMap,
        );

        // Expected value: 1000 * 1.5 = 1500
        expect.nat(result.totalMultiValue).equal(1500);
        expect.nat(result.submissionValues.size()).equal(1);
        expect.nat(result.submissionValues[0].1).equal(1500);

        // This 1500 should be aligned to 2000 (next multiple of 1000)
        // Initial supply
        let initialSupply = backingStore.getTotalSupply().value;

        // Mint tokens
        let mintResult = acquisitionMinter.mintAcquisitionTokens(
          submissions,
          priceMap,
        );

        // Verify minted amount is aligned to supply unit (1500 -> 2000)
        expect.nat(mintResult.mintedAmount.value).equal(2000);

        // Verify backing store total supply increased by aligned amount
        expect.nat(backingStore.getTotalSupply().value).equal(initialSupply + 2000);
      },
    );

    test(
      "tests different supply unit sizes",
      func() {
        // We need a fresh setup where we can control the supply unit
        let userAccounts = CompetitionTestUtils.createUserAccounts();
        let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");

        // Test different supply unit sizes
        let testSupplyUnit = func(supplyUnit : Nat, rawValue : Nat, expectedAlignedValue : Nat) {
          // Create backing store with specified supply unit
          let backingState : BackingTypes.BackingState = {
            var hasInitialized = false;
            var config = {
              supplyUnit = supplyUnit;
              totalSupply = 0;
              backingPairs = [];
              multiToken = CompetitionTestUtils.getMultiToken();
            };
          };

          let backingStore = BackingStore.BackingStore(backingState);
          backingStore.initialize(supplyUnit, CompetitionTestUtils.getMultiToken());

          // Add backing tokens
          backingStore.updateBackingTokens([{
            token = CompetitionTestUtils.getTestToken1();
            backingUnit = 10;
          }]);

          // Create backing operations
          let backingOps = BackingOperations.BackingOperations(
            backingStore,
            userAccounts,
            systemAccount,
          );

          // Create acquisition minter
          let acquisitionMinter = AcquisitionMinter.AcquisitionMinter(
            userAccounts,
            backingOps,
            backingStore,
            systemAccount,
          );

          // Create price map
          let priceMap = Map.HashMap<Text, Types.Price>(10, Text.equal, Text.hash);

          // Add price with exact ratio so the raw value will be exactly as specified
          priceMap.put(
            Principal.toText(CompetitionTestUtils.getTestToken1()),
            {
              baseToken = CompetitionTestUtils.getTestToken1();
              quoteToken = CompetitionTestUtils.getMultiToken();
              value = {
                value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
              }; // 1.0 ratio
            },
          );

          // Create submission that will produce the specified raw value
          let submissions = createFinalizedSubmissions(
            [CompetitionTestUtils.getTestToken1()],
            [rawValue] // Will produce exactly rawValue due to 1.0 price ratio
          );

          // Mint tokens
          let mintResult = acquisitionMinter.mintAcquisitionTokens(
            submissions,
            priceMap,
          );

          // Verify alignment
          expect.nat(mintResult.mintedAmount.value).equal(expectedAlignedValue);
        };

        // Test case 1: Supply unit 10
        // 9 should align to 10
        testSupplyUnit(10, 9, 10);

        // Test case 2: Supply unit 10
        // 10 should remain 10
        testSupplyUnit(10, 10, 10);

        // Test case 3: Supply unit 10
        // 11 should align to 20
        testSupplyUnit(10, 11, 20);

        // Test case 4: Supply unit 100
        // 99 should align to 100
        testSupplyUnit(100, 99, 100);

        // Test case 5: Supply unit 100
        // 101 should align to 200
        testSupplyUnit(100, 101, 200);

        // Test case 6: Supply unit 1
        // 1 should remain 1 (everything divisible by 1)
        testSupplyUnit(1, 1, 1);

        // Test case 7: Supply unit 1
        // 1000 should remain 1000 (everything divisible by 1)
        testSupplyUnit(1, 1000, 1000);
      },
    );
  },
);
