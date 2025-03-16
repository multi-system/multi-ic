import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import { suite; test; expect } "mo:test";

// Correct import paths for the required modules
import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionTypes "../../../multi_backend/types/CompetitionTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import CompetitionStore "../../../multi_backend/competition/CompetitionStore";
import CompetitionTestUtils "./CompetitionTestUtils";

// Test suite for the CompetitionStore
suite(
  "Competition Store",
  func() {
    // Create test data using functions from CompetitionTestUtils
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockTokenB = CompetitionTestUtils.getTestToken2();

    let approvedTokens = [mockTokenA, mockTokenB];
    let competitionPrices = [
      {
        baseToken = mockTokenA;
        quoteToken = mockSystemToken;
        value = { value = 100 };
      },
      {
        baseToken = mockTokenB;
        quoteToken = mockSystemToken;
        value = { value = 200 };
      },
    ];

    let initialState : CompetitionTypes.CompetitionState = {
      var hasInitialized = false;
      var competitionActive = false;
      var config = {
        govToken = mockGovToken;
        multiToken = mockSystemToken;
        approvedTokens = [];
        competitionPrices = [];
        govRate = { value = 5 };
        multiRate = { value = 10 };
        theta = { value = 5 };
        systemStakeGov = { value = 50 };
        systemStakeMulti = { value = 50 };
        competitionPeriodLength = 24 * 60 * 60 * 1_000_000_000; // 1 day
        competitionSpacing = 1 * 60 * 60 * 1_000_000_000; // 1 hour
        settlementDuration = 1 * 60 * 60 * 1_000_000_000; // 1 hour
        rewardDistributionFrequency = 24 * 60 * 60 * 1_000_000_000; // 1 day
        numberOfDistributionEvents = 7;
      };
      var submissions = [];
      var nextSubmissionId = 0;
      var totalGovStake = 0;
      var totalMultiStake = 0;
    };

    test(
      "initializes state correctly",
      func() {
        let store = CompetitionStore.CompetitionStore(initialState);

        // Initialize the store
        store.initialize(
          mockGovToken,
          mockSystemToken,
          { value = 5 },
          { value = 10 },
          { value = 5 },
          { value = 50 },
          { value = 50 },
          approvedTokens,
          competitionPrices,
          24 * 60 * 60 * 1_000_000_000, // 1 day
          1 * 60 * 60 * 1_000_000_000, // 1 hour
          1 * 60 * 60 * 1_000_000_000, // 1 hour
          24 * 60 * 60 * 1_000_000_000, // 1 day
          7,
        );

        // Verify initialization
        expect.bool(store.hasInitialized()).isTrue();
        expect.bool(store.isCompetitionActive()).isFalse();
        expect.principal(store.getGovToken()).equal(mockGovToken);
        expect.principal(store.getMultiToken()).equal(mockSystemToken);
        expect.nat(store.getApprovedTokens().size()).equal(2);
        expect.nat(store.getCompetitionPrices().size()).equal(2);
      },
    );

    test(
      "adds and retrieves submissions correctly",
      func() {
        let store = CompetitionStore.CompetitionStore(initialState);

        // Initialize the store
        store.initialize(
          mockGovToken,
          mockSystemToken,
          { value = 5 },
          { value = 10 },
          { value = 5 },
          { value = 50 },
          { value = 50 },
          approvedTokens,
          competitionPrices,
          24 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          24 * 60 * 60 * 1_000_000_000,
          7,
        );

        // Create a test submission
        let testSubmission = CompetitionTestUtils.createTestSubmission(
          0,
          Principal.fromText("aaaaa-aa"),
          #PreRound,
          mockTokenA,
        );

        // Add the submission
        store.addSubmission(testSubmission);

        // Verify submission was added
        let allSubmissions = store.getAllSubmissions();
        expect.nat(allSubmissions.size()).equal(1);

        // Check submission retrieval by ID
        let retrievedSubmission = store.getSubmission(0);
        switch (retrievedSubmission) {
          case null {
            expect.bool(false).isTrue(); // This should never happen - will fail the test
          };
          case (?submission) {
            expect.nat(submission.id).equal(0);
            expect.bool(submission.status == #PreRound).isTrue();
          };
        };

        // Check submission retrieval by status
        let statusSubmissions = store.getSubmissionsByStatus(#PreRound);
        expect.nat(statusSubmissions.size()).equal(1);
        expect.nat(statusSubmissions[0].id).equal(0);

        // Add another submission with different status
        let testSubmission2 = CompetitionTestUtils.createTestSubmission(
          1,
          Principal.fromText("aaaaa-aa"),
          #ActiveRound,
          mockTokenB,
        );
        store.addSubmission(testSubmission2);

        // Verify counts
        expect.nat(store.getAllSubmissions().size()).equal(2);
        expect.nat(store.getSubmissionsByStatus(#PreRound).size()).equal(1);
        expect.nat(store.getSubmissionsByStatus(#ActiveRound).size()).equal(1);
        expect.nat(store.getSubmissionCountByStatus(#PreRound)).equal(1);
      },
    );

    test(
      "updates stake rates correctly",
      func() {
        let store = CompetitionStore.CompetitionStore(initialState);

        // Initialize the store
        store.initialize(
          mockGovToken,
          mockSystemToken,
          { value = 5 },
          { value = 10 },
          { value = 5 },
          { value = 50 },
          { value = 50 },
          approvedTokens,
          competitionPrices,
          24 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          24 * 60 * 60 * 1_000_000_000,
          7,
        );

        // Verify initial rates
        expect.nat(store.getGovRate().value).equal(5);
        expect.nat(store.getMultiRate().value).equal(10);

        // Update rates
        store.updateStakeRates(
          { value = 8 },
          { value = 15 },
        );

        // Verify updated rates
        expect.nat(store.getGovRate().value).equal(8);
        expect.nat(store.getMultiRate().value).equal(15);
      },
    );

    test(
      "calculates volume limit correctly",
      func() {
        let store = CompetitionStore.CompetitionStore(initialState);

        // Initialize the store with theta = 5% properly scaled
        // 5% in proper scaling is 50,000,000 (5% of 1_000_000_000)
        store.initialize(
          mockGovToken,
          mockSystemToken,
          { value = 5 },
          { value = 10 },
          { value = CompetitionTestUtils.getFIVE_PERCENT() }, // 5% properly scaled
          { value = 50 },
          { value = 50 },
          approvedTokens,
          competitionPrices,
          24 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          1 * 60 * 60 * 1_000_000_000,
          24 * 60 * 60 * 1_000_000_000,
          7,
        );

        // Test with circulating supply of 1000
        let getCirculatingSupply = func() : Nat { 1000 };

        // Volume limit should be 5% of 1000 = 50
        let volumeLimit = store.getVolumeLimit(getCirculatingSupply);
        expect.nat(volumeLimit).equal(50);
      },
    );
  },
);
