import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
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
import TokenAccessHelper "../../helper/TokenAccessHelper";

module {
  public class DistributionProcessor() {

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
      // Calculate performances (only needed once)
      let performances = DistributionCalculator.calculatePerformances(positions, priceEvent);

      // Get unique stake tokens from the first position (all should have same tokens)
      if (positions.size() == 0) {
        return; // Nothing to distribute
      };

      let stakeTokens = Buffer.Buffer<Types.Token>(2);
      for ((token, _) in positions[0].stakes.vals()) {
        stakeTokens.add(token);
      };

      // Process each stake token type
      let rewardsByToken = Buffer.Buffer<(Types.Token, [Types.Amount])>(stakeTokens.size());

      for (token in stakeTokens.vals()) {
        // Extract stakes for this token from all positions
        let stakes = Array.map<RewardTypes.Position, Types.Amount>(
          positions,
          func(pos) : Types.Amount {
            switch (TokenAccessHelper.findInTokenArray(pos.stakes, token)) {
              case (?amount) { amount };
              case (null) { { token = token; value = 0 } };
            };
          },
        );

        // Calculate pool for this token type
        let pool = DistributionCalculator.calculateDistributionPool(
          stakes,
          distributionNumber,
          totalDistributions,
        );

        // Calculate final rewards for this token type
        let rewards = DistributionCalculator.calculateFinalRewards(
          performances,
          pool,
        );

        rewardsByToken.add((token, rewards));
      };

      // Execute transfers and update records
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

        // Collect payouts for this position
        let payouts = Buffer.Buffer<(Types.Token, Nat)>(rewardsByToken.size());

        // Execute transfers for each token type
        for ((token, rewards) in rewardsByToken.vals()) {
          let reward = rewards[i];

          if (not AmountOperations.isZero(reward)) {
            stakeVault.transferFromPoolToUser(account, reward);
          };

          // Add to payouts record
          payouts.add((token, reward.value));
        };

        // Update position payout records with flexible array
        ignore entryStore.updatePositionPayout(
          i,
          distributionNumber,
          Buffer.toArray(payouts),
        );
      };
    };
  };
};
