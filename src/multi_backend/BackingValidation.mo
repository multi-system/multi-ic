import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import ICRC2 "mo:icrc2-types";
import Types "./BackingTypes";

module {
  /// Verify token implements required ICRC2 interface
  public func verifyICRC2Token(tokenInfo : Types.TokenInfo) : async* Result.Result<(), Text> {
    try {
      // First verify the canisterId matches the token principal
      let tokenPrincipal = Principal.fromActor(tokenInfo.token);
      if (Principal.toText(tokenInfo.canisterId) != Principal.toText(tokenPrincipal)) {
        return #err("Not a valid ICRC2 token");
      };

      // Then try to call methods that should exist on any ICRC token
      try {
        let _ = await tokenInfo.token.icrc1_name();
        let _ = await tokenInfo.token.icrc1_symbol();
        #ok();
      } catch (_) {
        #err("Not a valid ICRC2 token");
      };
    } catch (_) {
      #err("Not a valid ICRC2 token");
    };
  };

  /// Validates backing token configuration including reserve quantities
  public func validateBacking(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.backingUnit == 0) {
        return #err("Backing units must be greater than 0");
      };

      if (pair.reserveQuantity == 0) {
        return #err("Reserve must be greater than 0");
      };

      let tokenPrincipal = Principal.fromActor(pair.tokenInfo.token);
      var isPresent = false;
      for (seenPrincipal in seen.vals()) {
        if (seenPrincipal == tokenPrincipal) {
          isPresent := true;
        };
      };
      if (isPresent) {
        return #err("Duplicate token in backing");
      };
      seen.add(tokenPrincipal);
    };

    #ok(());
  };

  /// Validates structure without checking reserves
  public func validateStructure(backing : [Types.BackingPair]) : Result.Result<(), Text> {
    if (backing.size() == 0) {
      return #err("Backing tokens cannot be empty");
    };

    let seen = Buffer.Buffer<Principal>(backing.size());
    for (pair in backing.vals()) {
      if (pair.backingUnit == 0) {
        return #err("Backing units must be greater than 0");
      };

      let tokenPrincipal = Principal.fromActor(pair.tokenInfo.token);
      var isPresent = false;
      for (seenPrincipal in seen.vals()) {
        if (seenPrincipal == tokenPrincipal) {
          isPresent := true;
        };
      };
      if (isPresent) {
        return #err("Duplicate token in backing");
      };
      seen.add(tokenPrincipal);
    };

    #ok(());
  };

  /// Validates complete backing configuration
  public func validateBackingConfig(config : Types.BackingConfig) : Result.Result<(), Text> {
    if (config.supplyUnit == 0) {
      return #err("Supply unit cannot be zero");
    };

    if (config.totalSupply % config.supplyUnit != 0) {
      return #err("Total supply must be divisible by supply unit");
    };

    validateStructure(config.backingPairs);
  };

  /// Full validation including interface checks
  public func validateBackingFull(config : Types.BackingConfig) : async* Result.Result<(), Text> {
    // First do structural validation
    switch (validateBackingConfig(config)) {
      case (#err(e)) { return #err(e) };
      case (#ok()) {};
    };

    // Then verify each token's implementation
    for (pair in config.backingPairs.vals()) {
      switch (await* verifyICRC2Token(pair.tokenInfo)) {
        case (#err(e)) { return #err(e) };
        case (#ok()) {};
      };
    };

    #ok();
  };
};
