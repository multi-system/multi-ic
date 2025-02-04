import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Types "../types/BackingTypes";
import BackingMath "./BackingMath";
import BackingValidation "./BackingValidation";

module {
  /// The backing store manages operations on backing state
  public class BackingStore(state : Types.BackingState) {
    public func initialize(
      initialSupplyUnit : Nat,
      initialBackingTokens : [Types.BackingPair],
    ) : Result.Result<(), Text> {
      if (state.hasInitialized) return #err("Already initialized");
      let config : Types.BackingConfig = {
        supplyUnit = initialSupplyUnit;
        totalSupply = 0;
        backingPairs = initialBackingTokens;
      };
      switch (BackingValidation.validateConfig(config)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          state.config := config;
          state.hasInitialized := true;
          #ok(());
        };
      };
    };

    public func getConfig() : Types.BackingConfig {
      state.config;
    };

    public func hasInitialized() : Bool {
      state.hasInitialized;
    };

    public func getBackingTokens() : [Types.BackingPair] {
      state.config.backingPairs;
    };

    public func getSupplyUnit() : Nat {
      state.config.supplyUnit;
    };

    public func getTotalSupply() : Nat {
      state.config.totalSupply;
    };

    public func updateTotalSupply(newSupply : Nat) : Result.Result<(), Text> {
      if (not state.hasInitialized) return #err("Not initialized");
      if (newSupply < state.config.supplyUnit) return #err("Supply cannot be less than unit");
      state.config := {
        state.config with totalSupply = newSupply;
      };
      #ok(());
    };

    public func updateBackingTokens(newTokens : [Types.BackingPair]) : Result.Result<(), Text> {
      if (not state.hasInitialized) return #err("Not initialized");
      switch (BackingValidation.validateStructure(newTokens)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          state.config := {
            state.config with backingPairs = newTokens;
          };
          #ok(());
        };
      };
    };

    public func validateBackingUpdate(amount : Nat) : Result.Result<(), Text> {
      if (not state.hasInitialized) return #err("Not initialized");
      if (amount % state.config.supplyUnit != 0) return #err("Amount must be multiple of supply unit");
      #ok(());
    };
  };
};
