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
import AmountOperations "../financial/AmountOperations";

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

    public func processIssue(caller : Types.Account, multiAmount : Types.Amount) : Result.Result<(), Error.OperationError> {
      let config = store.getConfig();

      switch (
        BackingValidation.validateBackingTokenTransfer(
          multiAmount,
          caller,
          store.getSupplyUnit(),
          store.getBackingTokens(),
          virtualAccounts,
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(transfers)) {
          for (amount in transfers.vals()) {
            virtualAccounts.transfer({
              from = caller;
              to = systemAccount;
              amount = amount;
            });
          };

          virtualAccounts.mint(caller, multiAmount);

          let currentSupply = store.getTotalSupply();
          let newSupply = AmountOperations.add(currentSupply, multiAmount);
          store.updateTotalSupply(newSupply);

          #ok(());
        };
      };
    };

    public func processRedeem(caller : Types.Account, multiAmount : Types.Amount) : Result.Result<(), Error.OperationError> {
      let config = store.getConfig();
      let currentSupply = store.getTotalSupply();

      switch (
        BackingValidation.validateRedeemAmount(
          multiAmount,
          currentSupply,
          store.getSupplyUnit(),
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      switch (
        BackingValidation.validateRedeemBalance(
          multiAmount,
          caller,
          virtualAccounts,
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };

      switch (
        BackingValidation.validateBackingTokenTransfer(
          multiAmount,
          systemAccount,
          store.getSupplyUnit(),
          store.getBackingTokens(),
          virtualAccounts,
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(transfers)) {
          for (amount in transfers.vals()) {
            virtualAccounts.transfer({
              from = systemAccount;
              to = caller;
              amount = amount;
            });
          };

          virtualAccounts.burn(caller, multiAmount);

          if (not AmountOperations.canSubtract(currentSupply, multiAmount)) {
            return #err(#InvalidAmount({ reason = "Failed to update total supply"; amount = multiAmount.value }));
          };

          let newSupply = AmountOperations.subtract(currentSupply, multiAmount);
          store.updateTotalSupply(newSupply);

          #ok(());
        };
      };
    };

    public func processSupplyIncrease(changeAmount : Types.Amount) : Result.Result<(), Error.OperationError> {
      let currentSupply = store.getTotalSupply();

      switch (BackingValidation.validateSupplyChange(changeAmount, true, currentSupply, store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          let newSupply = AmountOperations.add(currentSupply, changeAmount);
          updateSupply(newSupply);
          #ok(());
        };
      };
    };

    public func processSupplyDecrease(changeAmount : Types.Amount) : Result.Result<(), Error.OperationError> {
      let currentSupply = store.getTotalSupply();

      switch (BackingValidation.validateSupplyChange(changeAmount, false, currentSupply, store.getSupplyUnit())) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          if (not AmountOperations.canSubtract(currentSupply, changeAmount)) {
            return #err(#InvalidAmount({ reason = "Failed to update supply"; amount = changeAmount.value }));
          };

          let newSupply = AmountOperations.subtract(currentSupply, changeAmount);
          updateSupply(newSupply);
          #ok(());
        };
      };
    };

    private func updateSupply(newSupply : Types.Amount) {
      store.updateTotalSupply(newSupply);
      updateBackingRatios();
    };

    public func updateBackingRatios() {
      let totalSupply = store.getTotalSupply();
      let supplyUnit = store.getSupplyUnit();
      let backingTokens = store.getBackingTokens();

      let eta = BackingMath.calculateEta(totalSupply, supplyUnit);
      let backingUnits = Buffer.Buffer<Nat>(backingTokens.size());

      for (pair in backingTokens.vals()) {
        let reserveAmount = virtualAccounts.getBalance(systemAccount, pair.token);
        let unit = BackingMath.calculateBackingUnit(reserveAmount, eta);
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
