import Result "mo:base/Result";
import Types "../types/BackingTypes";
import Error "../error/Error";
import Principal "mo:base/Principal";
import VirtualAccounts "../ledger/VirtualAccounts";
import BackingMath "./BackingMath";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Option "mo:base/Option";

module {
  public func isTokenApproved(
    tokenId : Principal,
    backingTokens : [Types.BackingPair],
  ) : Result.Result<Types.BackingPair, Error.InitError> {
    let foundToken = Array.find<Types.BackingPair>(
      backingTokens,
      func(pair) = Principal.equal(pair.tokenInfo.canisterId, tokenId),
    );

    switch (foundToken) {
      case (null) { #err(#TokenNotApproved(tokenId)) };
      case (?token) { #ok(token) };
    };
  };

  public func isTokenAlreadyInBackingPairs(
    tokenInfo : Types.TokenInfo,
    backingPairs : [Types.BackingPair],
  ) : Bool {
    for (pair in backingPairs.vals()) {
      if (Principal.equal(pair.tokenInfo.canisterId, tokenInfo.canisterId)) {
        return true;
      };
    };
    return false;
  };

  public func createInsufficientBalanceError(
    token : Principal,
    required : Nat,
    balance : Nat,
  ) : Error.InsufficientBalanceError {
    {
      token = token;
      required = required;
      balance = balance;
    };
  };

  public func checkSufficientBalance<E>(
    principal : Principal,
    tokenId : Principal,
    requiredAmount : Nat,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    makeError : (Error.InsufficientBalanceError) -> E,
  ) : Result.Result<Nat, E> {
    let balance = virtualAccounts.getBalance(principal, tokenId);
    if (balance < requiredAmount) {
      let error = createInsufficientBalanceError(tokenId, requiredAmount, balance);
      return #err(makeError(error));
    };
    #ok(balance);
  };

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

    if (isTokenAlreadyInBackingPairs(tokenInfo, store.getConfig().backingPairs)) {
      return #err(#TokenAlreadyApproved(tokenInfo.canisterId));
    };
    #ok(());
  };

  public func validateNoTokenDuplicates(
    tokens : [Types.TokenInfo]
  ) : Result.Result<(), Error.InitError> {
    let seen = Buffer.Buffer<Principal>(tokens.size());

    for (token in tokens.vals()) {
      for (seenToken in seen.vals()) {
        if (Principal.equal(seenToken, token.canisterId)) {
          return #err(#DuplicateToken(token.canisterId));
        };
      };
      seen.add(token.canisterId);
    };

    #ok(());
  };

  public func validateInitialization(
    supplyUnit : Nat,
    initialTokens : [Types.BackingPair],
    store : {
      hasInitialized : () -> Bool;
      getBackingTokens : () -> [Types.BackingPair];
    },
  ) : Result.Result<(), Error.InitError> {
    if (store.hasInitialized()) {
      return #err(#AlreadyInitialized);
    };

    if (supplyUnit == 0) {
      return #err(#InvalidSupplyUnit);
    };

    let tokenInfos = Array.map<Types.BackingPair, Types.TokenInfo>(
      initialTokens,
      func(pair) : Types.TokenInfo = pair.tokenInfo,
    );

    switch (validateNoTokenDuplicates(tokenInfos)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    for (pair in initialTokens.vals()) {
      if (pair.backingUnit == 0) {
        return #err(#InvalidBackingUnit(pair.tokenInfo.canisterId));
      };

      switch (isTokenApproved(pair.tokenInfo.canisterId, store.getBackingTokens())) {
        case (#err(e)) return #err(e);
        case (#ok(_)) {};
      };
    };

    #ok(());
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

      switch (
        checkSufficientBalance<Error.OperationError>(
          from,
          pair.tokenInfo.canisterId,
          requiredAmount,
          virtualAccounts,
          func(e) { #InsufficientBalance(e) },
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(_)) {};
      };

      transfers.add((pair.tokenInfo.canisterId, requiredAmount));
    };
    #ok(Buffer.toArray(transfers));
  };

  public func validateRedeemAmount(
    amount : Nat,
    totalSupply : Nat,
    supplyUnit : Nat,
  ) : Result.Result<(), Error.OperationError> {
    switch (validateSupplyUnitDivisible(amount, supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    if (amount > totalSupply) {
      return #err(#InvalidAmount({ reason = "Cannot redeem more than total supply"; amount = amount }));
    };

    #ok(());
  };

  public func validateRedeemBalance(
    amount : Nat,
    caller : Principal,
    multiToken : Principal,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) : Result.Result<(), Error.OperationError> {
    switch (
      checkSufficientBalance<Error.OperationError>(
        caller,
        multiToken,
        amount,
        virtualAccounts,
        func(e) { #InsufficientBalance(e) },
      )
    ) {
      case (#err(e)) return #err(e);
      case (#ok(_)) {};
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
