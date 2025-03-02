import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Error "../error/Error";

module {
  public class BackingStore(state : BackingTypes.BackingState) {
    public func addBackingToken(token : Types.Token) {
      let newPair = {
        token = token;
        backingUnit = 0;
      };
      state.config := {
        state.config with
        backingPairs = Array.append(state.config.backingPairs, [newPair]);
      };
    };

    public func initialize(
      supplyUnit : Nat,
      multiToken : Types.Token,
      governanceToken : Types.Token,
    ) {
      state.config := {
        state.config with
        supplyUnit = supplyUnit;
        totalSupply = 0;
        multiToken = multiToken;
        governanceToken = governanceToken;
      };
      state.hasInitialized := true;
    };

    public func updateTotalSupply(newSupply : Nat) {
      state.config := {
        state.config with totalSupply = newSupply;
      };
    };

    public func updateBackingTokens(newTokens : [BackingTypes.BackingPair]) {
      state.config := {
        state.config with backingPairs = newTokens;
      };
    };

    // Query functions
    public func getConfig() : BackingTypes.BackingConfig { state.config };
    public func hasInitialized() : Bool { state.hasInitialized };
    public func getBackingTokens() : [BackingTypes.BackingPair] {
      state.config.backingPairs;
    };
    public func getSupplyUnit() : Nat { state.config.supplyUnit };
    public func getTotalSupply() : Nat { state.config.totalSupply };
  };
};
