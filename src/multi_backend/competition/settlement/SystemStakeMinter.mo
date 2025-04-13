import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import SystemStakeTypes "../../types/SystemStakeTypes";
import VirtualAccounts "../../custodial/VirtualAccounts";
import BackingOperations "../../backing/BackingOperations";
import BackingStore "../../backing/BackingStore";
import BackingMath "../../backing/BackingMath";

/**
 * SystemStakeMinter handles minting Multi and Gov tokens for system stake
 * participation as a single operation.
 */
module {
  public class SystemStakeMinter(
    userAccounts : VirtualAccounts.VirtualAccounts,
    backingOps : BackingOperations.BackingOperations,
    backingStore : BackingStore.BackingStore,
    govToken : Types.Token,
    systemAccount : Types.Account,
  ) {
    private let multiToken = backingStore.getMultiToken();

    /**
     * Mint both Multi and Gov tokens for system stake in a single operation.
     * The Multi tokens go through supply increase processing.
     *
     * @param systemStake The system stake information
     * @returns The minted Multi amount and Gov amount
     */
    public func mintSystemStake(
      systemStake : SystemStakeTypes.SystemStake
    ) : {
      multiAmount : Types.Amount;
      govAmount : Types.Amount;
    } {
      // Get supply unit from backing store
      let supplyUnit = backingStore.getSupplyUnit();

      // Verify system stake is valid
      if (systemStake.multiSystemStake.value == 0) {
        Debug.trap("Critical error: System Multi stake is zero");
      };

      if (not Principal.equal(systemStake.multiSystemStake.token, multiToken)) {
        Debug.trap("Critical error: System Multi stake token mismatch");
      };

      if (not Principal.equal(systemStake.govSystemStake.token, govToken)) {
        Debug.trap("Critical error: System Gov stake token mismatch");
      };

      let multiAmount = systemStake.multiSystemStake;
      let govAmount = systemStake.govSystemStake;

      // Align Multi amount to supply units using BackingMath
      let rawValue = multiAmount.value;
      let alignedValue = BackingMath.alignToSupplyUnit(rawValue, supplyUnit);

      let alignedMultiAmount : Types.Amount = {
        token = multiToken;
        value = alignedValue;
      };

      // Process supply increase for Multi tokens only
      switch (backingOps.processSupplyIncrease(alignedMultiAmount)) {
        case (#err(e)) {
          Debug.trap(
            "Critical error: Failed to increase supply for system stake: " #
            debug_show (e)
          );
        };
        case (#ok()) {
          // Mint Multi tokens to the system account
          userAccounts.mint(systemAccount, alignedMultiAmount);

          // Mint Gov tokens to the system account
          userAccounts.mint(systemAccount, govAmount);

          {
            multiAmount = alignedMultiAmount;
            govAmount = govAmount;
          };
        };
      };
    };
  };
};
