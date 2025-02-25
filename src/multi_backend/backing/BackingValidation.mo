import Result "mo:base/Result";
import Types "../types/BackingTypes";
import Error "../types/Error";
import Principal "mo:base/Principal";
import VirtualAccounts "../ledger/VirtualAccounts";
import BackingMath "./BackingMath";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Option "mo:base/Option";

module {
  public func validateSupplyUnitDivisible(amount : Nat, supplyUnit : Nat) : Result.Result<(), Error.OperationError> {
    if (supplyUnit == 0) {
      return #err(#InvalidAmount({ reason = "Supply unit cannot be zero"; amount = supplyUnit }));
    };
    if (amount % supplyUnit != 0) {
      return #err(#InvalidAmount({ reason = "Amount must be divisible by supply unit"; amount = amount }));
    };
    #ok(());
  };

  public func validateTokenApproval(
    tokenInfo : Types.TokenInfo,
    store : {
      hasInitialized : () -> Bool;
      getConfig : () -> Types.BackingConfig;
    },
  ) : Result.Result<(), Error.ApprovalError> {
    if (store.hasInitialized()) {
      return #err(#AlreadyInitialized);
    };

    for (pair in store.getConfig().backingPairs.vals()) {
      if (Principal.equal(pair.tokenInfo.canisterId, tokenInfo.canisterId)) {
        return #err(#TokenAlreadyApproved(tokenInfo.canisterId));
      };
    };
    #ok(());
  };

  public func validateInitialization(
    supplyUnit : Nat,
    initialSupply : Nat,
    store : {
      hasInitialized : () -> Bool;
      getBackingTokens : () -> [Types.BackingPair];
    },
  ) : Result.Result<(), Error.InitError> {
    if (store.hasInitialized()) {
      return #err(#AlreadyInitialized);
    };
    if (supplyUnit == 0 or initialSupply % supplyUnit != 0) {
      return #err(#InvalidSupplyUnit);
    };
    #ok(());
  };

  public func validateInitialAmounts(
    initialAmounts : [(Principal, Nat)],
    backingTokens : [Types.BackingPair],
    caller : Principal,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) : Result.Result<[(Principal, Nat)], Error.InitError> {
    let transfers = Buffer.Buffer<(Principal, Nat)>(initialAmounts.size());

    for ((tokenId, amount) in initialAmounts.vals()) {
      // First check if token is approved
      let isApproved = Array.find<Types.BackingPair>(
        backingTokens,
        func(pair) = Principal.equal(pair.tokenInfo.canisterId, tokenId),
      );

      if (Option.isNull(isApproved)) {
        return #err(#TokenNotApproved(tokenId));
      };

      // Then check balance
      let balance = virtualAccounts.getBalance(caller, tokenId);
      if (balance < amount) {
        return #err(#InsufficientBalance({ token = tokenId; required = amount; balance = balance }));
      };
      transfers.add((tokenId, amount));
    };
    #ok(Buffer.toArray(transfers));
  };

  public func validateBackingTokenTransfer(
    amount : Nat,
    from : Principal,
    supplyUnit : Nat,
    backingTokens : [Types.BackingPair],
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) : Result.Result<[(Principal, Nat)], Error.OperationError> {
    switch (validateSupplyUnitDivisible(amount, supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    let transfers = Buffer.Buffer<(Principal, Nat)>(backingTokens.size());
    let eta = BackingMath.calculateEta(amount, supplyUnit);

    for (pair in backingTokens.vals()) {
      let requiredAmount = pair.backingUnit * eta;
      let balance = virtualAccounts.getBalance(from, pair.tokenInfo.canisterId);
      if (balance < requiredAmount) {
        return #err(#InsufficientBalance({ token = pair.tokenInfo.canisterId; required = requiredAmount; balance = balance }));
      };
      transfers.add((pair.tokenInfo.canisterId, requiredAmount));
    };
    #ok(Buffer.toArray(transfers));
  };

  public func validateRedeemBalance(
    amount : Nat,
    caller : Principal,
    multiToken : Principal,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) : Result.Result<(), Error.OperationError> {
    let balance = virtualAccounts.getBalance(caller, multiToken);
    if (balance < amount) {
      return #err(#InsufficientBalance({ token = multiToken; required = amount; balance = balance }));
    };
    #ok(());
  };

  public func validateSupplyChange(
    amount : Nat,
    isIncrease : Bool,
    currentSupply : Nat,
    supplyUnit : Nat,
  ) : Result.Result<(), Error.OperationError> {
    switch (validateSupplyUnitDivisible(amount, supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    if (not isIncrease and currentSupply < amount) {
      return #err(#InvalidSupplyChange({ currentSupply = currentSupply; requestedChange = amount; reason = "Cannot decrease supply by more than current supply" }));
    };
    #ok(());
  };
};
