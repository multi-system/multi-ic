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
    },
    virtualAccounts : {
      getBalance : (Types.Account, Types.Token) -> Nat;
    },
    systemAccount : Types.Account,
  ) {
    // QUERY RESPONSE FORMATTERS

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
