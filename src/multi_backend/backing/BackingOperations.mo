import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Types "../types/BackingTypes";
import Error "../error/Error";
import VirtualAccounts "../ledger/VirtualAccounts";
import BackingMath "./BackingMath";
import BackingStore "./BackingStore";
import BackingValidation "./BackingValidation";

module {
  public class BackingOperationsImpl(
    store : BackingStore.BackingStore,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    systemAccount : Principal,
  ) {

    public func processInitialize(
      caller : Principal,
      backingTokens : [Types.BackingPair],
      supplyUnit : Nat,
      multiToken : Types.TokenInfo,
      governanceToken : Types.TokenInfo,
    ) : Result.Result<(), Error.InitError> {
      switch (BackingValidation.validateInitialization(supplyUnit, backingTokens, store)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          store.initialize(supplyUnit, multiToken, governanceToken);
          store.updateBackingTokens(backingTokens);
          #ok(());
        };
      };
    };

    public func processIssue(caller : Principal, amount : Nat) : Result.Result<(), Error.OperationError> {
      let config = store.getConfig();

      switch (
        BackingValidation.validateBackingTokenTransfer(
          amount,
          caller,
          store.getSupplyUnit(),
          store.getBackingTokens(),
          virtualAccounts,
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(transfers)) {
          for ((tokenId, amount) in transfers.vals()) {
            virtualAccounts.transfer({
              from = caller;
              to = systemAccount;
              token = tokenId;
              amount = amount;
            });
          };

          virtualAccounts.mint(caller, config.multiToken.canisterId, amount);
          store.updateTotalSupply(store.getTotalSupply() + amount);
          #ok(());
        };
      };
    };

    public func processRedeem(caller : Principal, amount : Nat) : Result.Result<(), Error.OperationError> {
      let config = store.getConfig();

      switch (BackingValidation.validateRedeemAmount(amount, store.getTotalSupply(), store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      switch (BackingValidation.validateRedeemBalance(amount, caller, config.multiToken.canisterId, virtualAccounts)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      switch (
        BackingValidation.validateBackingTokenTransfer(
          amount,
          systemAccount,
          store.getSupplyUnit(),
          store.getBackingTokens(),
          virtualAccounts,
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(transfers)) {
          for ((tokenId, amount) in transfers.vals()) {
            virtualAccounts.transfer({
              from = systemAccount;
              to = caller;
              token = tokenId;
              amount = amount;
            });
          };

          virtualAccounts.burn(caller, config.multiToken.canisterId, amount);
          store.updateTotalSupply(store.getTotalSupply() - amount);
          #ok(());
        };
      };
    };

    public func processSupplyIncrease(amount : Nat) : Result.Result<(), Error.OperationError> {
      let currentSupply = store.getTotalSupply();

      switch (BackingValidation.validateSupplyChange(amount, true, currentSupply, store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          updateSupply(currentSupply + amount);
          #ok(());
        };
      };
    };

    public func processSupplyDecrease(amount : Nat) : Result.Result<(), Error.OperationError> {
      let currentSupply = store.getTotalSupply();

      switch (BackingValidation.validateSupplyChange(amount, false, currentSupply, store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          updateSupply(currentSupply - amount);
          #ok(());
        };
      };
    };

    private func updateSupply(newSupply : Nat) {
      store.updateTotalSupply(newSupply);
      updateBackingRatios();
    };

    private func updateBackingRatios() {
      let totalSupply = store.getTotalSupply();
      let supplyUnit = store.getSupplyUnit();
      let backingTokens = store.getBackingTokens();

      let eta = BackingMath.calculateEta(totalSupply, supplyUnit);
      let backingUnits = Buffer.Buffer<Nat>(backingTokens.size());

      for (pair in backingTokens.vals()) {
        let reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.tokenInfo.canisterId);
        let unit = BackingMath.calculateBackingUnit(reserveQuantity, eta);
        backingUnits.add(unit);
      };

      let newPairs = Array.mapEntries<Types.BackingPair, Types.BackingPair>(
        backingTokens,
        func(pair : Types.BackingPair, index : Nat) : Types.BackingPair {
          {
            tokenInfo = pair.tokenInfo;
            backingUnit = backingUnits.get(index);
          };
        },
      );

      store.updateBackingTokens(newPairs);
    };
  };
};
