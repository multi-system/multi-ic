import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

// Import existing modules
import Types "../types/BackingTypes";
import Error "../error/Error";
import BackingValidation "../backing/BackingValidation";
import Messages "./Messages";
import ErrorMapping "../error/ErrorMapping";

module {
  public class ApiHelper(
    backingStore : {
      hasInitialized : () -> Bool;
      getConfig : () -> Types.BackingConfig;
      addBackingToken : (Types.TokenInfo) -> ();
      getBackingTokens : () -> [Types.BackingPair];
      initialize : (Nat, Types.TokenInfo, Types.TokenInfo) -> ();
      updateBackingTokens : ([Types.BackingPair]) -> ();
      getTotalSupply : () -> Nat;
      getSupplyUnit : () -> Nat;
    },
    tokenRegistry : {
      approve : (Types.TokenInfo) -> Result.Result<(), Error.ApprovalError>;
      isApproved : (Principal) -> Bool;
      getApproved : () -> [Types.TokenInfo];
      size : () -> Nat;
    },
    virtualAccounts : {
      getBalance : (Principal, Principal) -> Nat;
    },
    systemAccount : Principal,
  ) {
    // ADMINISTRATIVE OPERATIONS

    public func approveToken(
      caller : Principal,
      owner : Principal,
      tokenInfo : Types.TokenInfo,
      addLedger : (Principal) -> async* Result.Result<(), Error.ApprovalError>,
    ) : async* Result.Result<(), Error.ApprovalError> {
      if (caller != owner) {
        return #err(#Unauthorized);
      };

      if (backingStore.hasInitialized()) {
        return #err(#AlreadyInitialized);
      };

      switch (BackingValidation.validateTokenApproval(tokenInfo, backingStore)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          if (tokenRegistry.isApproved(tokenInfo.canisterId)) {
            return #err(#TokenAlreadyApproved(tokenInfo.canisterId));
          };

          switch (tokenRegistry.approve(tokenInfo)) {
            case (#err(e)) {
              // e is already an Error.ApprovalError, so we can return it directly
              return #err(e);
            };
            case (#ok()) {
              let ledgerResult = await* addLedger(tokenInfo.canisterId);

              switch (ledgerResult) {
                case (#err(e)) return #err(e);
                case (#ok()) {
                  backingStore.addBackingToken(tokenInfo);
                  return #ok(());
                };
              };
            };
          };
        };
      };
    };

    public func initialize(
      caller : Principal,
      owner : Principal,
      request : Messages.InitializeRequest,
      processInitialize : (
        Principal,
        [Types.BackingPair],
        Nat,
        Types.TokenInfo,
        Types.TokenInfo,
      ) -> Result.Result<(), Error.InitError>,
    ) : Result.Result<(), Error.InitError> {
      if (caller != owner) {
        return #err(#Unauthorized);
      };

      let multiTokenInfo : Types.TokenInfo = {
        canisterId = request.multiToken.canisterId;
      };

      let governanceTokenInfo : Types.TokenInfo = {
        canisterId = request.governanceToken.canisterId;
      };

      let backingPairs = Array.map<{ canisterId : Principal; backingUnit : Nat }, Types.BackingPair>(
        request.backingTokens,
        func(token) : Types.BackingPair {
          {
            tokenInfo = { canisterId = token.canisterId };
            backingUnit = token.backingUnit;
          };
        },
      );

      return processInitialize(caller, backingPairs, request.supplyUnit, multiTokenInfo, governanceTokenInfo);
    };

    // USER OPERATIONS HELPERS

    public func validateDepositPreconditions(_ : Principal) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateWithdrawPreconditions(_ : Principal) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateIssuePreconditions(_ : Principal) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateRedeemPreconditions(_ : Principal) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    // QUERY FORMATTING

    public func formatBackingTokensResponse() : Messages.GetTokensResponse {
      let tokens = Array.map<Types.BackingPair, Messages.BackingTokenInfo>(
        backingStore.getBackingTokens(),
        func(pair : Types.BackingPair) : Messages.BackingTokenInfo {
          {
            tokenInfo = {
              canisterId = pair.tokenInfo.canisterId;
            };
            backingUnit = pair.backingUnit;
            reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.tokenInfo.canisterId);
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
      let multiTokenId = config.multiToken.canisterId;
      let governanceTokenId = config.governanceToken.canisterId;

      let backingTokensInfo = Array.map<Types.BackingPair, Messages.BackingTokenInfo>(
        backingStore.getBackingTokens(),
        func(pair : Types.BackingPair) : Messages.BackingTokenInfo {
          {
            tokenInfo = {
              canisterId = pair.tokenInfo.canisterId;
            };
            backingUnit = pair.backingUnit;
            reserveQuantity = virtualAccounts.getBalance(systemAccount, pair.tokenInfo.canisterId);
          };
        },
      );

      return #ok({
        initialized = true;
        totalSupply = config.totalSupply;
        supplyUnit = config.supplyUnit;
        multiToken = { canisterId = multiTokenId };
        governanceToken = { canisterId = governanceTokenId };
        backingTokens = backingTokensInfo;
      });
    };

    public func getGovernanceTokenIdResponse() : Principal {
      backingStore.getConfig().governanceToken.canisterId;
    };

    public func getBalanceResponse(user : Principal, token : Principal) : Messages.GetBalanceResponse {
      return #ok(virtualAccounts.getBalance(user, token));
    };

    public func getTotalSupplyResponse() : Messages.GetBalanceResponse {
      return #ok(backingStore.getTotalSupply());
    };

    public func getMultiTokenBalanceResponse(user : Principal) : Messages.GetBalanceResponse {
      let multiToken = backingStore.getConfig().multiToken;
      return #ok(virtualAccounts.getBalance(user, multiToken.canisterId));
    };
  };
};
