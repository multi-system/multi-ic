import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Error "../error/Error";
import BackingValidation "../backing/BackingValidation";
import Messages "./Messages";

module {
  public class ApiHelper(
    backingStore : {
      hasInitialized : () -> Bool;
      getConfig : () -> BackingTypes.BackingConfig;
      addBackingToken : (Types.Token) -> ();
      getBackingTokens : () -> [BackingTypes.BackingPair];
      initialize : (Nat, Types.Token, Types.Token) -> ();
      updateBackingTokens : ([BackingTypes.BackingPair]) -> ();
      getTotalSupply : () -> Nat;
      getSupplyUnit : () -> Nat;
    },
    tokenRegistry : {
      approve : (Types.Token) -> Result.Result<(), Error.ApprovalError>;
      isApproved : (Types.Token) -> Bool;
      getApproved : () -> [Types.Token];
      size : () -> Nat;
    },
    virtualAccounts : {
      getBalance : (Types.Account, Types.Token) -> Nat;
    },
    systemAccount : Types.Account,
  ) {
    // ADMINISTRATIVE OPERATIONS

    public func approveToken(
      caller : Types.Account,
      owner : Types.Account,
      tokenRequest : Messages.TokenRequest,
      addLedger : (Types.Token) -> async* Result.Result<(), Error.ApprovalError>,
    ) : async* Result.Result<(), Error.ApprovalError> {
      let token : Types.Token = tokenRequest.canisterId;

      if (caller != owner) {
        return #err(#Unauthorized);
      };

      if (backingStore.hasInitialized()) {
        return #err(#AlreadyInitialized);
      };

      switch (BackingValidation.validateTokenApproval(token, backingStore)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          if (tokenRegistry.isApproved(token)) {
            return #err(#TokenAlreadyApproved(token));
          };

          switch (tokenRegistry.approve(token)) {
            case (#err(e)) {
              return #err(e);
            };
            case (#ok()) {
              let ledgerResult = await* addLedger(token);

              switch (ledgerResult) {
                case (#err(e)) return #err(e);
                case (#ok()) {
                  backingStore.addBackingToken(token);
                  return #ok(());
                };
              };
            };
          };
        };
      };
    };

    public func initialize(
      caller : Types.Account,
      owner : Types.Account,
      request : Messages.InitializeRequest,
      processInitialize : (
        [BackingTypes.BackingPair],
        Nat,
        Types.Token,
        Types.Token,
      ) -> Result.Result<(), Error.InitError>,
    ) : Result.Result<(), Error.InitError> {
      if (caller != owner) {
        return #err(#Unauthorized);
      };

      let multiToken : Types.Token = request.multiToken.canisterId;
      let governanceToken : Types.Token = request.governanceToken.canisterId;

      let backingPairs = Array.map<{ canisterId : Principal; backingUnit : Nat }, BackingTypes.BackingPair>(
        request.backingTokens,
        func(tokenInfo) : BackingTypes.BackingPair {
          {
            token = tokenInfo.canisterId;
            backingUnit = tokenInfo.backingUnit;
          };
        },
      );

      return processInitialize(backingPairs, request.supplyUnit, multiToken, governanceToken);
    };

    // USER OPERATIONS HELPERS

    public func validateDepositPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateWithdrawPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateIssuePreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateRedeemPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    // QUERY FORMATTING

    public func formatBackingTokensResponse() : Messages.GetTokensResponse {
      let tokens = Array.map<BackingTypes.BackingPair, Messages.BackingTokenInfo>(
        backingStore.getBackingTokens(),
        func(pair : BackingTypes.BackingPair) : Messages.BackingTokenInfo {
          {
            tokenInfo = { canisterId = pair.token };
            backingUnit = pair.backingUnit;
            reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.token);
          };
        },
      );
      return #ok(tokens);
    };

    public func formatSystemInfoResponse() : Messages.GetSystemInfoResponse {
      if (not backingStore.hasInitialized()) {
        return #err(#NotInitialized);
      };

      let config = backingStore.getConfig();

      let backingTokensInfo = Array.map<BackingTypes.BackingPair, Messages.BackingTokenInfo>(
        backingStore.getBackingTokens(),
        func(pair : BackingTypes.BackingPair) : Messages.BackingTokenInfo {
          {
            tokenInfo = { canisterId = pair.token };
            backingUnit = pair.backingUnit;
            reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.token);
          };
        },
      );

      return #ok({
        initialized = true;
        totalSupply = config.totalSupply;
        supplyUnit = config.supplyUnit;
        multiToken = { canisterId = config.multiToken };
        governanceToken = { canisterId = config.governanceToken };
        backingTokens = backingTokensInfo;
      });
    };

    public func getGovernanceTokenIdResponse() : Principal {
      backingStore.getConfig().governanceToken;
    };

    public func getBalanceResponse(user : Types.Account, token : Types.Token) : Messages.GetBalanceResponse {
      return #ok(virtualAccounts.getBalance(user, token));
    };

    public func getTotalSupplyResponse() : Messages.GetBalanceResponse {
      return #ok(backingStore.getTotalSupply());
    };

    public func getMultiTokenBalanceResponse(user : Types.Account) : Messages.GetBalanceResponse {
      let multiToken = backingStore.getConfig().multiToken;
      return #ok(virtualAccounts.getBalance(user, multiToken));
    };
  };
};
