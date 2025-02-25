import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Types "../types/BackingTypes";
import Error "../types/Error";

module {
  public class BackingStore(state : Types.BackingState) {
    public func addBackingToken(tokenInfo : Types.TokenInfo) {
      let newPair = {
        tokenInfo = tokenInfo;
        backingUnit = 0;
      };
      state.config := {
        state.config with
        backingPairs = Array.append(state.config.backingPairs, [newPair]);
      };
    };

    public func initialize(
      supplyUnit : Nat,
      initialSupply : Nat,
      multiToken : Types.TokenInfo,
    ) {
      state.config := {
        state.config with
        supplyUnit = supplyUnit;
        totalSupply = initialSupply;
        multiToken = multiToken;
      };
      state.hasInitialized := true;
    };

    public func updateTotalSupply(newSupply : Nat) {
      state.config := {
        state.config with totalSupply = newSupply;
      };
    };

    public func updateBackingTokens(newTokens : [Types.BackingPair]) {
      state.config := {
        state.config with backingPairs = newTokens;
      };
    };

    // Query functions
    public func getConfig() : Types.BackingConfig { state.config };
    public func hasInitialized() : Bool { state.hasInitialized };
    public func getBackingTokens() : [Types.BackingPair] {
      state.config.backingPairs;
    };
    public func getSupplyUnit() : Nat { state.config.supplyUnit };
    public func getTotalSupply() : Nat { state.config.totalSupply };
  };
};
