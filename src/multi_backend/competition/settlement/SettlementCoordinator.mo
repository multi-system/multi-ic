import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";
import Map "mo:base/HashMap";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import SubmissionTypes "../../types/SubmissionTypes";
import SystemStakeTypes "../../types/SystemStakeTypes";
import SettlementTypes "../../types/SettlementTypes";
import UserPositionSettlement "./UserPositionSettlement";
import PhantomPositionSettlement "./PhantomPositionSettlement";
import AcquisitionMinter "./AcquisitionMinter";
import SystemStakeMinter "./SystemStakeMinter";
import VirtualAccounts "../../custodial/VirtualAccounts";
import BackingOperations "../../backing/BackingOperations";
import BackingStore "../../backing/BackingStore";

/**
 * Coordinates the settlement process by handling user submissions
 * and system phantom positions with proper supply unit alignment.
 */
module {
  public class SettlementCoordinator(
    userAccounts : VirtualAccounts.VirtualAccounts,
    stakeAccounts : VirtualAccounts.VirtualAccounts,
    backingOps : BackingOperations.BackingOperations,
    backingStore : BackingStore.BackingStore,
    govToken : Types.Token,
    systemAccount : Types.Account,
  ) {
    private let multiToken = backingStore.getMultiToken();

    private let acquisitionMinter = AcquisitionMinter.AcquisitionMinter(
      userAccounts,
      backingOps,
      backingStore,
      systemAccount,
    );

    private let systemStakeMinter = SystemStakeMinter.SystemStakeMinter(
      userAccounts,
      backingOps,
      backingStore,
      govToken,
      systemAccount,
    );

    private let userSettlement = UserPositionSettlement.UserPositionSettlement(
      userAccounts,
      stakeAccounts,
      multiToken,
      systemAccount,
    );

    private let phantomSettlement = PhantomPositionSettlement.PhantomPositionSettlement();

    /**
     * Executes the settlement process for all finalized submissions and system positions.
     *
     * @param finalizedSubmissions List of submissions in #Finalized status
     * @param systemStake System stake information with phantom positions
     * @param executionPrices List of execution prices for each token
     * @returns A SettlementRecord with the results
     */
    public func executeSettlement(
      finalizedSubmissions : [SubmissionTypes.Submission],
      systemStake : SystemStakeTypes.SystemStake,
      executionPrices : [SettlementTypes.ExecutionPriceInfo],
    ) : SettlementTypes.SettlementRecord {
      let priceMap = Map.HashMap<Text, Types.Price>(20, Text.equal, Text.hash);

      // Convert execution prices to a map for easier lookup
      for (priceInfo in executionPrices.vals()) {
        priceMap.put(Principal.toText(priceInfo.token), priceInfo.executionPrice);
      };

      // Track all settled positions
      let positions = Buffer.Buffer<RewardTypes.Position>(finalizedSubmissions.size() + systemStake.phantomPositions.size());

      // Store token amounts in a map for efficient updates
      let tokenAmounts = Map.HashMap<Types.Token, Types.Amount>(10, Principal.equal, Principal.hash);

      // STEP 1: MINT ACQUISITION TOKENS
      // Mint Multi tokens for acquisitions in a single operation
      let acquisitionResult = acquisitionMinter.mintAcquisitionTokens(
        finalizedSubmissions,
        priceMap,
      );

      let multiMinted = acquisitionResult.mintedAmount;
      let submissionValues = acquisitionResult.submissionValues;

      // Convert submission values to a map for quick lookup
      let valueMap = Map.HashMap<SubmissionTypes.SubmissionId, Nat>(
        finalizedSubmissions.size(),
        Nat.equal,
        func(id : Nat) : Nat32 { Nat32.fromNat(id) },
      );

      for ((id, value) in submissionValues.vals()) {
        valueMap.put(id, value);
      };

      // Calculate total value for ratio calculations
      var totalValue = 0;
      for ((_, value) in submissionValues.vals()) {
        totalValue += value;
      };

      // STEP 2: PROCESS USER SUBMISSIONS
      for (submission in finalizedSubmissions.vals()) {
        // Skip any submissions that aren't ready
        if (submission.status != #Finalized or submission.adjustedQuantity == null) {
          Debug.trap(
            "Critical error: Submission " # debug_show (submission.id) #
            " in executeSettlement is not properly finalized"
          );
        };

        // Get price for this token
        let price = switch (priceMap.get(Principal.toText(submission.token))) {
          case (null) {
            Debug.trap(
              "Critical error: Missing execution price for token " #
              Principal.toText(submission.token)
            );
          };
          case (?p) { p };
        };

        // Get submission value
        let submissionValue = switch (valueMap.get(submission.id)) {
          case (null) {
            Debug.trap(
              "Critical error: Missing calculated value for submission " #
              debug_show (submission.id)
            );
          };
          case (?v) { v };
        };

        // Settle the submission
        let position = userSettlement.settleUserSubmission(
          submission,
          price,
          submissionValue,
          totalValue,
          multiMinted,
        );

        positions.add(position);

        // Track token amounts
        switch (tokenAmounts.get(position.quantity.token)) {
          case (null) {
            tokenAmounts.put(position.quantity.token, position.quantity);
          };
          case (?existingAmount) {
            tokenAmounts.put(
              position.quantity.token,
              {
                token = position.quantity.token;
                value = existingAmount.value + position.quantity.value;
              },
            );
          };
        };
      };

      // STEP 3: RECORD PHANTOM POSITIONS
      for ((token, amount) in systemStake.phantomPositions.vals()) {
        // Create phantom position record
        let position = phantomSettlement.createPhantomPosition(
          token,
          amount,
          systemStake,
        );

        positions.add(position);

        // Track token amounts
        switch (tokenAmounts.get(position.quantity.token)) {
          case (null) {
            tokenAmounts.put(position.quantity.token, position.quantity);
          };
          case (?existingAmount) {
            tokenAmounts.put(
              position.quantity.token,
              {
                token = position.quantity.token;
                value = existingAmount.value + position.quantity.value;
              },
            );
          };
        };
      };

      // STEP 4: MINT SYSTEM STAKE TOKENS
      let systemStakeResult = systemStakeMinter.mintSystemStake(systemStake);

      // STEP 5: UPDATE BACKING RATIOS
      // Update backing ratios after all token transfers to ensure accurate reserve representation
      backingOps.updateBackingRatios();

      // Convert HashMap to array for return value
      let tokenAmountsArray = Buffer.Buffer<(Types.Token, Types.Amount)>(tokenAmounts.size());
      for ((token, amount) in tokenAmounts.entries()) {
        tokenAmountsArray.add((token, amount));
      };

      // Create the settlement record
      {
        tokenAmounts = Buffer.toArray(tokenAmountsArray);
        multiMinted = multiMinted;
        systemStakeMinted = systemStakeResult.multiAmount;
        timestamp = Time.now();
      };
    };

    /**
     * Creates execution price information for all tokens based on competition prices.
     * In a future version, this would implement market price discovery.
     *
     * @param competitionPrices The competition prices for tokens
     * @returns ExecutionPriceInfo array
     */
    public func createExecutionPrices(
      competitionPrices : [Types.Price]
    ) : [SettlementTypes.ExecutionPriceInfo] {
      // Simple implementation - just uses competition prices
      Array.map<Types.Price, SettlementTypes.ExecutionPriceInfo>(
        competitionPrices,
        func(price : Types.Price) : SettlementTypes.ExecutionPriceInfo {
          {
            token = price.baseToken;
            executionPrice = price;
          };
        },
      );
    };
  };
};
