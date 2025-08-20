import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import { suite; test; expect } "mo:test";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../../../../multi_backend/types/Types";
import Error "../../../../multi_backend/error/Error";
import RewardTypes "../../../../multi_backend/types/RewardTypes";
import SubmissionTypes "../../../../multi_backend/types/SubmissionTypes";
import VirtualAccounts "../../../../multi_backend/custodial/VirtualAccounts";
import UserPositionSettlement "../../../../multi_backend/competition/settlement/UserPositionSettlement";
import RatioOperations "../../../../multi_backend/financial/RatioOperations";
import CompetitionTestUtils "../CompetitionTestUtils";
import AccountTypes "../../../../multi_backend/types/AccountTypes";

suite(
  "User Position Settlement",
  func() {
    // Setup test environment
    let setupTest = func() : (
      UserPositionSettlement.UserPositionSettlement,
      VirtualAccounts.VirtualAccounts,
      VirtualAccounts.VirtualAccounts,
      Principal,
      SubmissionTypes.Submission,
    ) {
      // Create virtual accounts
      let userAccounts = CompetitionTestUtils.createUserAccounts();
      let stakeAccounts = VirtualAccounts.VirtualAccounts(
        StableHashMap.init<Types.Account, AccountTypes.BalanceMap>()
      );

      // Create test tokens and principals
      let multiToken = CompetitionTestUtils.getMultiToken();
      let testToken = CompetitionTestUtils.getTestToken1();
      let govToken = CompetitionTestUtils.getGovToken();
      // Use a valid Principal format for the system account
      let systemAccount = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
      let userAccount = CompetitionTestUtils.getUserPrincipal();

      // Create UserPositionSettlement
      let userPositionSettlement = UserPositionSettlement.UserPositionSettlement(
        userAccounts,
        stakeAccounts,
        multiToken,
        systemAccount,
      );

      // Add tokens to stake account
      let tokenAmount : Types.Amount = {
        token = testToken;
        value = 10_000;
      };

      let govStake : Types.Amount = {
        token = govToken;
        value = 1_000;
      };

      let multiStake : Types.Amount = {
        token = multiToken;
        value = 500;
      };

      stakeAccounts.mint(userAccount, tokenAmount);
      stakeAccounts.mint(userAccount, govStake);
      stakeAccounts.mint(userAccount, multiStake);

      // Add multi tokens to system account
      userAccounts.mint(systemAccount, { token = multiToken; value = 50_000 });

      // Create a test submission with flexible stakes array
      let submission : SubmissionTypes.Submission = {
        id = 0;
        participant = userAccount;
        stakes = [
          (govToken, govStake),
          (multiToken, multiStake),
        ];
        token = testToken;
        proposedQuantity = tokenAmount;
        timestamp = 0;
        status = #Finalized;
        rejectionReason = null;
        adjustedQuantity = ?tokenAmount; // Same as proposed for simplicity
        soldQuantity = null;
        executionPrice = null;
        positionId = null;
      };

      (userPositionSettlement, userAccounts, stakeAccounts, systemAccount, submission);
    };

    test(
      "settles user submission correctly",
      func() {
        let (settlement, userAccounts, stakeAccounts, systemAccount, submission) = setupTest();

        // Create execution price
        let price : Types.Price = {
          baseToken = submission.token;
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
          }; // 1.0 ratio
        };

        // Calculate the proportion of minted tokens for this submission
        let submissionValue = 10_000; // Equals token quantity (10,000) * price (1.0)
        let totalValue = 50_000; // Example total value of all submissions
        let mintedAmount : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 25_000; // Total minted for all submissions
        };

        // Save the initial Multi token balance before settlement
        let initialMultiBalance = userAccounts.getBalance(submission.participant, CompetitionTestUtils.getMultiToken()).value;

        // Call the function under test
        let position = settlement.settleUserSubmission(
          submission,
          price,
          submissionValue,
          totalValue,
          mintedAmount,
        );

        // Verify position record
        assert (position.quantity.value == 10_000);
        assert (Principal.equal(position.quantity.token, CompetitionTestUtils.getTestToken1()));

        // Check stakes array contains the expected values
        assert (position.stakes.size() == 2);
        let (govToken, govStakeAmount) = position.stakes[0];
        let (multiToken, multiStakeAmount) = position.stakes[1];
        assert (Principal.equal(govToken, CompetitionTestUtils.getGovToken()));
        assert (govStakeAmount.value == 1_000);
        assert (Principal.equal(multiToken, CompetitionTestUtils.getMultiToken()));
        assert (multiStakeAmount.value == 500);

        assert (position.isSystem == false);
        assert (position.submissionId == ?0);

        // Calculate expected user share of minted tokens
        // share = submissionValue / totalValue = 10,000 / 50,000 = 0.2 (20%)
        // userMultiAmount = mintedAmount * share = 25,000 * 0.2 = 5,000
        let expectedUserReward = 5_000;

        // Verify token flows
        // 1. Tokens should be removed from stake account
        assert (stakeAccounts.getBalance(submission.participant, submission.token).value == 0);

        // 2. Tokens should be in the user account (temporarily)
        // 3. Then transferred to system account
        assert (userAccounts.getBalance(systemAccount, submission.token).value == 10_000);

        // 4. User should receive Multi tokens as reward
        // The final balance should be the initial balance plus the reward
        assert (userAccounts.getBalance(submission.participant, CompetitionTestUtils.getMultiToken()).value == initialMultiBalance + expectedUserReward);

        // 5. System account should have fewer Multi tokens now
        assert (userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value == 50_000 - expectedUserReward);
      },
    );

    test(
      "settles submissions with different values correctly",
      func() {
        let (settlement, userAccounts, stakeAccounts, systemAccount, submission) = setupTest();

        // Create execution price (2.0 this time)
        let price : Types.Price = {
          baseToken = submission.token;
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT() * 2;
          }; // 2.0 ratio
        };

        // With price 2.0, the submission value is 20,000
        let submissionValue = 20_000; // Token quantity (10,000) * price (2.0)
        let totalValue = 100_000; // Example total value of all submissions
        let mintedAmount : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 50_000; // Total minted for all submissions
        };

        // Save the initial Multi token balance before settlement
        let initialMultiBalance = userAccounts.getBalance(submission.participant, CompetitionTestUtils.getMultiToken()).value;

        // Call the function under test
        let position = settlement.settleUserSubmission(
          submission,
          price,
          submissionValue,
          totalValue,
          mintedAmount,
        );

        // Calculate expected user share of minted tokens
        // share = submissionValue / totalValue = 20,000 / 100,000 = 0.2 (20%)
        // userMultiAmount = mintedAmount * share = 50,000 * 0.2 = 10,000
        let expectedUserReward = 10_000;

        // Verify token flows
        assert (stakeAccounts.getBalance(submission.participant, submission.token).value == 0);
        assert (userAccounts.getBalance(systemAccount, submission.token).value == 10_000);
        assert (userAccounts.getBalance(submission.participant, CompetitionTestUtils.getMultiToken()).value == initialMultiBalance + expectedUserReward);
        assert (userAccounts.getBalance(systemAccount, CompetitionTestUtils.getMultiToken()).value == 50_000 - expectedUserReward);
      },
    );

    test(
      "handles edge cases correctly",
      func() {
        let (settlement, userAccounts, stakeAccounts, systemAccount, originalSubmission) = setupTest();

        // Create a submission with a very small value
        let smallTokenAmount : Types.Amount = {
          token = CompetitionTestUtils.getTestToken1();
          value = 1;
        };

        let smallSubmission = {
          originalSubmission with
          proposedQuantity = smallTokenAmount;
          adjustedQuantity = ?smallTokenAmount;
        };

        // Update stake account balance
        stakeAccounts.burn(originalSubmission.participant, originalSubmission.proposedQuantity);
        stakeAccounts.mint(originalSubmission.participant, smallTokenAmount);

        // Create price
        let price : Types.Price = {
          baseToken = smallSubmission.token;
          quoteToken = CompetitionTestUtils.getMultiToken();
          value = {
            value = CompetitionTestUtils.getONE_HUNDRED_PERCENT();
          }; // 1.0 ratio
        };

        // Very small relative to total
        let submissionValue = 1;
        let totalValue = 1_000_000;
        let mintedAmount : Types.Amount = {
          token = CompetitionTestUtils.getMultiToken();
          value = 100_000;
        };

        // Save the initial Multi token balance before settlement
        let initialMultiBalance = userAccounts.getBalance(smallSubmission.participant, CompetitionTestUtils.getMultiToken()).value;

        // Call the function under test
        let position = settlement.settleUserSubmission(
          smallSubmission,
          price,
          submissionValue,
          totalValue,
          mintedAmount,
        );

        // Calculate expected reward (might be 0 due to rounding)
        // share = 1/1,000,000 = 0.000001
        // reward = 100,000 * 0.000001 = 0.1 (rounds to 0 for integers)
        let expectedReward = 0;

        // Verify still handled correctly
        assert (stakeAccounts.getBalance(smallSubmission.participant, smallSubmission.token).value == 0);
        assert (userAccounts.getBalance(systemAccount, smallSubmission.token).value == 1);
        assert (userAccounts.getBalance(smallSubmission.participant, CompetitionTestUtils.getMultiToken()).value == initialMultiBalance + expectedReward);
      },
    );
  },
);
