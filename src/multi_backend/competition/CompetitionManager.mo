import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time"; // Added missing Time import

import Types "../types/Types";
import Error "../error/Error";
import CompetitionStore "./CompetitionStore";
import StakingManager "./staking/StakingManager";
import StakeVault "./staking/StakeVault";
import CompetitionTypes "../types/CompetitionTypes";
import SubmissionTypes "../types/SubmissionTypes";
import SystemStakeTypes "../types/SystemStakeTypes";
import BackingTypes "../types/BackingTypes";
import FinalizeStakingRound "./staking/FinalizeStakingRound";

module {
  // Type for the output from the staking round
  public type StakingRoundOutput = {
    finalizedSubmissions : [SubmissionTypes.Submission];
    systemStake : SystemStakeTypes.SystemStake;
    govRate : Types.Ratio;
    multiRate : Types.Ratio;
    volumeLimit : Nat;
  };

  // Function type for starting the settlement phase
  public type SettlementInitiator = (StakingRoundOutput) -> Result.Result<(), Error.CompetitionError>;

  public class CompetitionManager(
    store : CompetitionStore.CompetitionStore,
    stakeVault : StakeVault.StakeVault,
    getCirculatingSupply : () -> Nat,
    getBackingTokens : () -> [BackingTypes.BackingPair],
    startSettlement : SettlementInitiator,
  ) {
    private let stakingManager = StakingManager.StakingManager(
      store,
      stakeVault,
      getCirculatingSupply,
      getBackingTokens,
    );

    // Initialize the competition system
    public func initialize(
      govToken : Types.Token,
      multiToken : Types.Token,
      initialGovRate : Types.Ratio,
      initialMultiRate : Types.Ratio,
      theta : Types.Ratio,
      systemStakeGov : Types.Ratio,
      systemStakeMulti : Types.Ratio,
      approvedTokens : [Types.Token],
      competitionPrices : [Types.Price],
      competitionPeriodLength : Time.Time,
      competitionSpacing : Time.Time,
      settlementDuration : Time.Time,
      rewardDistributionFrequency : Time.Time,
      numberOfDistributionEvents : Nat,
    ) : Result.Result<(), Error.InitError> {
      if (store.hasInitialized()) {
        return #err(#AlreadyInitialized);
      };
      // Initialize the competition store with all parameters
      store.initialize(
        govToken,
        multiToken,
        initialGovRate,
        initialMultiRate,
        theta,
        systemStakeGov,
        systemStakeMulti,
        approvedTokens,
        competitionPrices,
        competitionPeriodLength,
        competitionSpacing,
        settlementDuration,
        rewardDistributionFrequency,
        numberOfDistributionEvents,
      );
      #ok(());
    };

    // Start the staking round
    public func startStakingRound() : Result.Result<(), Error.CompetitionError> {
      if (not store.hasInitialized()) {
        return #err(#OperationFailed("Competition system not initialized"));
      };
      if (store.isCompetitionActive()) {
        return #err(#InvalidPhase({ current = "active"; required = "inactive" }));
      };
      store.setCompetitionActive(true);
      #ok(());
    };

    // End the staking round, finalize all submissions, and start settlement
    public func endStakingRound() : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      if (not store.hasInitialized()) {
        return #err(#OperationFailed("Competition system not initialized"));
      };
      if (not store.isCompetitionActive()) {
        return #err(#InvalidPhase({ current = "inactive"; required = "active" }));
      };

      // Process all queued submissions first
      stakingManager.processQueue();

      // Then finalize all submissions
      switch (finalizeStakingRound()) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok(result)) {
          // Set competition to inactive after successful finalization
          store.setCompetitionActive(false);

          // Prepare data for settlement phase
          let stakingOutput = {
            finalizedSubmissions = store.getSubmissionsByStatus(#PostRound);
            systemStake = result.systemStake;
            govRate = result.finalGovRate;
            multiRate = result.finalMultiRate;
            volumeLimit = result.volumeLimit;
          };

          // Start settlement and handle the result
          switch (startSettlement(stakingOutput)) {
            case (#err(e)) {
              Debug.print("Error starting settlement: " # debug_show (e));
              // We could propagate this error if needed
            };
            case (#ok(_)) {
              Debug.print("Settlement started successfully");
            };
          };

          #ok(result);
        };
      };
    };

    // Accept a stake request - either process immediately or queue for later
    public func acceptStakeRequest(
      govStake : Types.Amount,
      account : Types.Account,
      proposedToken : Types.Token,
      shouldQueue : Bool,
    ) : Result.Result<{ submissionId : SubmissionTypes.SubmissionId; tokenQuantity : Types.Amount; isQueued : Bool }, Error.CompetitionError> {
      stakingManager.acceptStakeRequest(govStake, account, proposedToken, shouldQueue);
    };

    // Finalize staking round - internal method
    private func finalizeStakingRound() : Result.Result<FinalizeStakingRound.FinalizationResult, Error.CompetitionError> {
      FinalizeStakingRound.finalizeRound(
        store,
        stakeVault,
        getCirculatingSupply,
        getBackingTokens,
      );
    };

    // Get all queued submissions
    public func getQueuedSubmissions() : [SubmissionTypes.Submission] {
      stakingManager.getQueuedSubmissions();
    };

    // Get number of queued submissions
    public func getQueueSize() : Nat {
      stakingManager.getQueueSize();
    };
  };
};
