import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Map "mo:base/HashMap";
import Text "mo:base/Text";

import Types "../../types/Types";
import SubmissionTypes "../../types/SubmissionTypes";
import VirtualAccounts "../../custodial/VirtualAccounts";
import BackingOperations "../../backing/BackingOperations";
import BackingStore "../../backing/BackingStore";
import BackingMath "../../backing/BackingMath";
import RatioOperations "../../financial/RatioOperations";

/**
 * AcquisitionMinter calculates and mints Multi tokens needed for all
 * user token acquisitions in a single operation, respecting supply units.
 */
module {
  public class AcquisitionMinter(
    userAccounts : VirtualAccounts.VirtualAccounts,
    backingOps : BackingOperations.BackingOperations,
    backingStore : BackingStore.BackingStore,
    systemAccount : Types.Account,
  ) {
    private let multiToken = backingStore.getMultiToken();

    /**
     * Calculate Multi token values for a collection of submissions
     * without performing any minting or token transfers.
     *
     * @param submissions The submissions to calculate values for
     * @param priceMap A map of token principals to execution prices
     * @returns Total Multi value and per-submission Multi values
     */
    public func calculateMultiValues(
      submissions : [SubmissionTypes.Submission],
      priceMap : Map.HashMap<Text, Types.Price>,
    ) : {
      totalMultiValue : Nat;
      submissionValues : [(SubmissionTypes.SubmissionId, Nat)];
    } {
      var totalMultiValue = 0;
      let submissionValues = Buffer.Buffer<(SubmissionTypes.SubmissionId, Nat)>(submissions.size());

      for (submission in submissions.vals()) {
        // Verify submission is properly finalized
        if (submission.status != #PostRound or submission.adjustedQuantity == null) {
          Debug.trap(
            "Critical error: Submission " # debug_show (submission.id) #
            " is not properly finalized (status: " # debug_show (submission.status) #
            ", adjustedQuantity: " # debug_show (submission.adjustedQuantity) # ")"
          );
        };

        // Properly unwrap the optional value
        let tokenAmount = switch (submission.adjustedQuantity) {
          case (null) {
            Debug.trap("Critical error: Adjusted quantity is null even though we already checked it");
          };
          case (?amount) {
            amount;
          };
        };

        // Get price for this token
        let price = switch (priceMap.get(Principal.toText(tokenAmount.token))) {
          case (null) {
            Debug.trap(
              "Critical error: Missing execution price for token " #
              Principal.toText(tokenAmount.token) # " in calculateMultiValues"
            );
          };
          case (?p) { p };
        };

        // Calculate Multi value
        let multiValue = RatioOperations.applyToAmount(
          tokenAmount,
          price.value,
        ).value;

        totalMultiValue += multiValue;
        submissionValues.add((submission.id, multiValue));
      };

      {
        totalMultiValue;
        submissionValues = Buffer.toArray(submissionValues);
      };
    };

    /**
     * Mint Multi tokens for all acquisitions in a single operation,
     * respecting supply units.
     *
     * @param submissions The submissions that are being settled
     * @param priceMap A map of token principals to execution prices
     * @returns The actual amount minted (aligned to supply units) and per-submission values
     */
    public func mintAcquisitionTokens(
      submissions : [SubmissionTypes.Submission],
      priceMap : Map.HashMap<Text, Types.Price>,
    ) : {
      mintedAmount : Types.Amount;
      submissionValues : [(SubmissionTypes.SubmissionId, Nat)];
    } {
      // Get supply unit from backing store
      let supplyUnit = backingStore.getSupplyUnit();

      // First calculate the raw value needed
      let calculationResult = calculateMultiValues(submissions, priceMap);
      let rawValue = calculationResult.totalMultiValue;

      // Align to supply units using BackingMath
      let alignedValue = BackingMath.alignToSupplyUnit(rawValue, supplyUnit);

      // Create the Multi amount to mint
      let multiAmount : Types.Amount = {
        token = multiToken;
        value = alignedValue;
      };

      // Process supply increase in one operation
      switch (backingOps.processSupplyIncrease(multiAmount)) {
        case (#err(e)) {
          Debug.trap(
            "Critical error: Failed to increase supply for acquisitions: " #
            debug_show (e)
          );
        };
        case (#ok()) {
          // Mint to system account
          userAccounts.mint(systemAccount, multiAmount);

          // Return the actual minted amount and per-submission values
          {
            mintedAmount = multiAmount;
            submissionValues = calculationResult.submissionValues;
          };
        };
      };
    };
  };
};
