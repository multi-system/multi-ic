import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import { suite; test; expect } "mo:test";
import Types "../../../multi_backend/types/Types";
import Error "../../../multi_backend/error/Error";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import SubmissionTypes "../../../multi_backend/types/SubmissionTypes";
import CompetitionEntryStore "../../../multi_backend/competition/CompetitionEntryStore";
import CompetitionTestUtils "./CompetitionTestUtils";

// Test suite for the CompetitionEntryStore
suite(
  "Competition Entry Store",
  func() {
    // Create test data using functions from CompetitionTestUtils
    let mockSystemToken = CompetitionTestUtils.getMultiToken();
    let mockGovToken = CompetitionTestUtils.getGovToken();
    let mockTokenA = CompetitionTestUtils.getTestToken1();
    let mockTokenB = CompetitionTestUtils.getTestToken2();

    test(
      "handles submissions correctly",
      func() {
        let entryStore = CompetitionTestUtils.createCompetitionEntryStore();

        // Create a test submission
        let testSubmission = CompetitionTestUtils.createTestSubmission(
          0,
          Principal.fromText("aaaaa-aa"),
          #Queued,
          mockTokenA,
        );

        // Add the submission
        entryStore.addSubmission(testSubmission);

        // Verify submission was added
        let allSubmissions = entryStore.getAllSubmissions();
        expect.nat(allSubmissions.size()).equal(1);

        // Check submission retrieval by ID
        let retrievedSubmission = entryStore.getSubmission(0);
        switch (retrievedSubmission) {
          case null {
            expect.bool(false).isTrue(); // This should never happen - will fail the test
          };
          case (?submission) {
            expect.nat(submission.id).equal(0);
            expect.bool(submission.status == #Queued).isTrue();
          };
        };

        // Check submission retrieval by status
        let statusSubmissions = entryStore.getSubmissionsByStatus(#Queued);
        expect.nat(statusSubmissions.size()).equal(1);
        expect.nat(statusSubmissions[0].id).equal(0);

        // Add another submission with different status
        let testSubmission2 = CompetitionTestUtils.createTestSubmission(
          1,
          Principal.fromText("aaaaa-aa"),
          #Staked,
          mockTokenB,
        );
        entryStore.addSubmission(testSubmission2);

        // Verify counts
        expect.nat(entryStore.getAllSubmissions().size()).equal(2);
        expect.nat(entryStore.getSubmissionsByStatus(#Queued).size()).equal(1);
        expect.nat(entryStore.getSubmissionsByStatus(#Staked).size()).equal(1);
        expect.nat(entryStore.getSubmissionCountByStatus(#Queued)).equal(1);
      },
    );

    test(
      "updates stake rates correctly",
      func() {
        let entryStore = CompetitionTestUtils.createCompetitionEntryStore();

        // Get initial rates
        let initialGovRate = entryStore.getGovRate();
        let initialMultiRate = entryStore.getMultiRate();

        // Update rates to higher values
        let newGovRate = { value = initialGovRate.value * 2 };
        let newMultiRate = { value = initialMultiRate.value * 2 };

        entryStore.updateStakeRates(newGovRate, newMultiRate);

        // Verify updated rates
        expect.nat(entryStore.getAdjustedGovRate().value).equal(newGovRate.value);
        expect.nat(entryStore.getAdjustedMultiRate().value).equal(newMultiRate.value);
      },
    );

    test(
      "calculates volume limit correctly",
      func() {
        let entryStore = CompetitionTestUtils.createCompetitionEntryStore();

        // Test with circulating supply of 1000
        let getCirculatingSupply = func() : Nat { 1000 };

        // Calculate volume limit
        let volumeLimit = entryStore.calculateVolumeLimit(getCirculatingSupply);

        // Volume limit should be theta (20%) of 1000 = 200
        expect.nat(volumeLimit).equal(200);
      },
    );

    test(
      "updates competition status correctly",
      func() {
        let entryStore = CompetitionTestUtils.createCompetitionEntryStore();

        // Initial status should be AcceptingStakes (from test helper)
        expect.bool(entryStore.getStatus() == #AcceptingStakes).isTrue();

        // Change status to various states
        entryStore.updateStatus(#Finalizing);
        expect.bool(entryStore.getStatus() == #Finalizing).isTrue();

        entryStore.updateStatus(#Settlement);
        expect.bool(entryStore.getStatus() == #Settlement).isTrue();

        entryStore.updateStatus(#Distribution);
        expect.bool(entryStore.getStatus() == #Distribution).isTrue();

        // Check that endTime was set when status changed to Distribution
        let entryDataDistribution = entryStore.getData();
        expect.bool(entryDataDistribution.endTime != null).isTrue();

        // Create a new store for Completed test
        let entryStore2 = CompetitionTestUtils.createCompetitionEntryStore();
        entryStore2.updateStatus(#Completed);

        // Verify status updated
        expect.bool(entryStore2.getStatus() == #Completed).isTrue();

        // Check that endTime was set when status changed to Completed
        let entryDataCompleted = entryStore2.getData();
        expect.bool(entryDataCompleted.endTime != null).isTrue();
      },
    );
  },
);
