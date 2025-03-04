import Array "mo:base/Array";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import AmountOperations "../financial/AmountOperations";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";

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
    ) {
      state.config := {
        state.config with
        supplyUnit = supplyUnit;
        totalSupply = 0;
        multiToken = multiToken;
      };
      state.hasInitialized := true;
    };

    public func updateTotalSupply(amount : Types.Amount) {
      if (amount.token != state.config.multiToken) {
        Debug.trap("Token mismatch: expected " # Principal.toText(state.config.multiToken) # " but got " # Principal.toText(amount.token));
      };
      state.config := {
        state.config with totalSupply = amount.value;
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
    public func getTotalSupply() : Types.Amount {
      {
        token = state.config.multiToken;
        value = state.config.totalSupply;
      };
    };
    public func getMultiToken() : Types.Token { state.config.multiToken };
  };
};
