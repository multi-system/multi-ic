import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Messages "./Messages";

module {
  public class ResponseHandler(
    backingStore : {
      hasInitialized : () -> Bool;
      getConfig : () -> BackingTypes.BackingConfig;
      getBackingTokens : () -> [BackingTypes.BackingPair];
      getTotalSupply : () -> Nat;
      getSupplyUnit : () -> Nat;
      getMultiToken : () -> Types.Token;
    },
    virtualAccounts : {
      getBalance : (Types.Account, Types.Token) -> Nat;
    },
    systemAccount : Types.Account,
    settings : {
      getGovernanceToken : () -> ?Types.Token;
    },
  ) {
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
      let governanceToken = switch (settings.getGovernanceToken()) {
        case (?token) token;
        case (null) Principal.fromText("aaaaa-aa");
      };

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
        governanceToken = { canisterId = governanceToken };
        backingTokens = backingTokensInfo;
      });
    };

    public func getGovernanceTokenIdResponse() : Principal {
      switch (settings.getGovernanceToken()) {
        case (?token) token;
        case (null) Principal.fromText("aaaaa-aa");
      };
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
