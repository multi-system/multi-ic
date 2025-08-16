import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Types "../../types/Types";
import SystemStakeTypes "../../types/SystemStakeTypes";
import VirtualAccounts "../../custodial/VirtualAccounts";
import BackingOperations "../../backing/BackingOperations";
import BackingStore "../../backing/BackingStore";
import BackingMath "../../backing/BackingMath";
import TokenAccessHelper "../../helper/TokenAccessHelper";

/**
 * SystemStakeMinter handles minting stake tokens for system stake
 * participation as a single operation.
 */
module {
  public class SystemStakeMinter(
    userAccounts : VirtualAccounts.VirtualAccounts,
    backingOps : BackingOperations.BackingOperations,
    backingStore : BackingStore.BackingStore,
    stakeTokenConfigs : [(Types.Token, Types.Ratio)], // Support n stake tokens
    systemAccount : Types.Account,
  ) {
    private let multiToken = backingStore.getMultiToken();

    /**
     * Mint all stake tokens for system stake in a single operation.
     * The Multi tokens go through supply increase processing and alignment.
     *
     * @param systemStake The system stake information
     * @returns The minted amounts for each stake token
     */
    public func mintSystemStake(
      systemStake : SystemStakeTypes.SystemStake
    ) : {
      mintedAmounts : [(Types.Token, Types.Amount)];
    } {
      let supplyUnit = backingStore.getSupplyUnit();

      if (systemStake.systemStakes.size() == 0) {
        Debug.trap("Critical error: System stake has no tokens");
      };

      var mintedAmounts = Buffer.Buffer<(Types.Token, Types.Amount)>(systemStake.systemStakes.size());

      // Process each stake token
      for ((token, amount) in systemStake.systemStakes.vals()) {
        if (Principal.equal(token, multiToken)) {
          // Multi token needs alignment and supply increase
          let alignedValue = BackingMath.alignToSupplyUnit(amount.value, supplyUnit);
          let alignedAmount : Types.Amount = {
            token = multiToken;
            value = alignedValue;
          };

          switch (backingOps.processSupplyIncrease(alignedAmount)) {
            case (#err(e)) {
              Debug.trap(
                "Critical error: Failed to increase supply for system stake: " #
                debug_show (e)
              );
            };
            case (#ok()) {
              userAccounts.mint(systemAccount, alignedAmount);
              mintedAmounts.add((token, alignedAmount)); // Return aligned amount
            };
          };
        } else {
          // Other stake tokens don't need alignment or supply processing
          userAccounts.mint(systemAccount, amount);
          mintedAmounts.add((token, amount));
        };
      };

      {
        mintedAmounts = Buffer.toArray(mintedAmounts);
      };
    };
  };
};
