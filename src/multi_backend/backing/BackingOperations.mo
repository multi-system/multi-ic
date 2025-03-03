import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Error "../error/Error";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingMath "./BackingMath";
import BackingStore "./BackingStore";
import BackingValidation "./BackingValidation";

module {
  public class BackingOperations(
    store : BackingStore.BackingStore,
    virtualAccounts : VirtualAccounts.VirtualAccounts,
    systemAccount : Types.Account,
  ) {

    public func processInitialize(
      backingTokens : [BackingTypes.BackingPair],
      supplyUnit : Nat,
      multiToken : Types.Token,
    ) : Result.Result<(), Error.InitError> {
      switch (BackingValidation.validateInitialization(supplyUnit, backingTokens, store)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          store.initialize(supplyUnit, multiToken);
          store.updateBackingTokens(backingTokens);
          #ok(());
        };
      };
    };

    public func processIssue(caller : Types.Account, amount : Nat) : Result.Result<(), Error.OperationError> {
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

          virtualAccounts.mint(caller, config.multiToken, amount);
          store.updateTotalSupply(store.getTotalSupply() + amount);
          #ok(());
        };
      };
    };

    public func processRedeem(caller : Types.Account, amount : Nat) : Result.Result<(), Error.OperationError> {
      let config = store.getConfig();

      switch (BackingValidation.validateRedeemAmount(amount, store.getTotalSupply(), store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      switch (BackingValidation.validateRedeemBalance(amount, caller, config.multiToken, virtualAccounts)) {
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

          virtualAccounts.burn(caller, config.multiToken, amount);
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
        let reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.token);
        let unit = BackingMath.calculateBackingUnit(reserveQuantity, eta);
        backingUnits.add(unit);
      };

      let newPairs = Array.mapEntries<BackingTypes.BackingPair, BackingTypes.BackingPair>(
        backingTokens,
        func(pair : BackingTypes.BackingPair, index : Nat) : BackingTypes.BackingPair {
          {
            token = pair.token;
            backingUnit = backingUnits.get(index);
          };
        },
      );

      store.updateBackingTokens(newPairs);
    };
  };
};
