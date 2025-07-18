import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import EventTypes "../../types/EventTypes";
import DistributionCalculator "./DistributionCalculator";
import StakeVault "../staking/StakeVault";
import CompetitionEntryStore "../CompetitionEntryStore";
import AmountOperations "../../financial/AmountOperations";

module {
  public class DistributionProcessor(
    govToken : Types.Token,
    multiToken : Types.Token,
  ) {

    public func processDistribution(
      positions : [RewardTypes.Position],
      priceEvent : EventTypes.PriceEvent,
      distributionNumber : Nat,
      totalDistributions : Nat,
      stakeVault : StakeVault.StakeVault,
      systemAccount : Types.Account,
      getPositionAccount : (RewardTypes.Position) -> ?Types.Account,
      entryStore : CompetitionEntryStore.CompetitionEntryStore,
    ) {
      // Step 1: Calculate performances (only needed once)
      let performances = DistributionCalculator.calculatePerformances(positions, priceEvent);

      // Step 2: Extract stakes by token type
      let govStakes = Array.map<RewardTypes.Position, Types.Amount>(
        positions,
        func(pos) { pos.govStake },
      );

      let multiStakes = Array.map<RewardTypes.Position, Types.Amount>(
        positions,
        func(pos) { pos.multiStake },
      );

      // Step 3: Calculate pools for each token type
      let govPool = DistributionCalculator.calculateDistributionPool(
        govStakes,
        distributionNumber,
        totalDistributions,
      );

      let multiPool = DistributionCalculator.calculateDistributionPool(
        multiStakes,
        distributionNumber,
        totalDistributions,
      );

      // Step 4: Calculate final rewards for each token type
      let govRewards = DistributionCalculator.calculateFinalRewards(
        performances,
        govPool,
      );

      let multiRewards = DistributionCalculator.calculateFinalRewards(
        performances,
        multiPool,
      );

      // Step 5: Execute transfers (side effects stay in processor)
      for (i in Iter.range(0, performances.size() - 1)) {
        let perf = performances[i];

        // Get account
        let account = if (perf.position.isSystem) {
          systemAccount;
        } else {
          switch (getPositionAccount(perf.position)) {
            case (?acc) { acc };
            case (null) { Debug.trap("No account for position") };
          };
        };

        // Execute transfers for each token type
        if (not AmountOperations.isZero(govRewards[i])) {
          stakeVault.transferFromPoolToUser(account, govRewards[i]);
        };

        if (not AmountOperations.isZero(multiRewards[i])) {
          stakeVault.transferFromPoolToUser(account, multiRewards[i]);
        };

        // Update position payout records
        ignore entryStore.updatePositionPayout(
          i,
          distributionNumber,
          govRewards[i].value,
          multiRewards[i].value,
        );
      };
    };
  };
};
