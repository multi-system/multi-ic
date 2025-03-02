import Result "mo:base/Result";
import BackingTypes "../types/BackingTypes";
import Types "../types/Types";
import Error "../error/Error";
import Principal "mo:base/Principal";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingMath "./BackingMath";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";

module {
  public func isTokenApproved(
    token : Types.Token,
    backingTokens : [BackingTypes.BackingPair],
  ) : Result.Result<BackingTypes.BackingPair, Error.InitError> {
    let foundToken = Array.find<BackingTypes.BackingPair>(
      backingTokens,
      func(pair) = Principal.equal(pair.token, token),
    );

    switch (foundToken) {
      case (null) { #err(#TokenNotApproved(token)) };
      case (?token) { #ok(token) };
    };
  };

  public func isTokenAlreadyInBackingPairs(
    token : Types.Token,
    backingPairs : [BackingTypes.BackingPair],
  ) : Bool {
    for (pair in backingPairs.vals()) {
      if (Principal.equal(pair.token, token)) {
        return true;
      };
    };
    return false;
  };

  public func createInsufficientBalanceError(
    token : Types.Token,
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
    principal : Types.Account,
    token : Types.Token,
    requiredAmount : Nat,
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
    makeError : (Error.InsufficientBalanceError) -> E,
  ) : Result.Result<Nat, E> {
    let balance = virtualAccounts.getBalance(principal, token);
    if (balance < requiredAmount) {
      let error = createInsufficientBalanceError(token, requiredAmount, balance);
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
    token : Types.Token,
    store : {
      hasInitialized : () -> Bool;
      getConfig : () -> BackingTypes.BackingConfig;
    },
  ) : Result.Result<(), Error.ApprovalError> {
    if (store.hasInitialized()) {
      return #err(#AlreadyInitialized);
    };

    if (isTokenAlreadyInBackingPairs(token, store.getConfig().backingPairs)) {
      return #err(#TokenAlreadyApproved(token));
    };
    #ok(());
  };

  public func validateNoTokenDuplicates(
    tokens : [Types.Token]
  ) : Result.Result<(), Error.InitError> {
    let seen = Buffer.Buffer<Types.Token>(tokens.size());

    for (token in tokens.vals()) {
      for (seenToken in seen.vals()) {
        if (Principal.equal(seenToken, token)) {
          return #err(#DuplicateToken(token));
        };
      };
      seen.add(token);
    };

    #ok(());
  };

  public func validateInitialization(
    supplyUnit : Nat,
    initialTokens : [BackingTypes.BackingPair],
    store : {
      hasInitialized : () -> Bool;
      getBackingTokens : () -> [BackingTypes.BackingPair];
    },
  ) : Result.Result<(), Error.InitError> {
    if (store.hasInitialized()) {
      return #err(#AlreadyInitialized);
    };

    if (supplyUnit == 0) {
      return #err(#InvalidSupplyUnit);
    };

    let tokens = Array.map<BackingTypes.BackingPair, Types.Token>(
      initialTokens,
      func(pair) : Types.Token = pair.token,
    );

    switch (validateNoTokenDuplicates(tokens)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    for (pair in initialTokens.vals()) {
      if (pair.backingUnit == 0) {
        return #err(#InvalidBackingUnit(pair.token));
      };

      switch (isTokenApproved(pair.token, store.getBackingTokens())) {
        case (#err(e)) return #err(e);
        case (#ok(_)) {};
      };
    };

    #ok(());
  };

  public func validateBackingTokenTransfer(
    amount : Nat,
    from : Types.Account,
    supplyUnit : Nat,
    backingTokens : [BackingTypes.BackingPair],
    virtualAccounts : VirtualAccounts.VirtualAccountManager,
  ) : Result.Result<[(Types.Token, Nat)], Error.OperationError> {
    switch (validateSupplyUnitDivisible(amount, supplyUnit)) {
      case (#err(e)) return #err(e);
      case (#ok()) {};
    };

    let transfers = Buffer.Buffer<(Types.Token, Nat)>(backingTokens.size());
    let eta = BackingMath.calculateEta(amount, supplyUnit);

    for (pair in backingTokens.vals()) {
      let requiredAmount = pair.backingUnit * eta;

      switch (
        checkSufficientBalance<Error.OperationError>(
          from,
          pair.token,
          requiredAmount,
          virtualAccounts,
          func(e) { #InsufficientBalance(e) },
        )
      ) {
        case (#err(e)) return #err(e);
        case (#ok(_)) {};
      };

      transfers.add((pair.token, requiredAmount));
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
    caller : Types.Account,
    multiToken : Types.Token,
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
