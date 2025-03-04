import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Messages "./Messages";
import Debug "mo:base/Debug";

module {
  public class ResponseHandler(
    backingStore : {
      hasInitialized : () -> Bool;
      getConfig : () -> BackingTypes.BackingConfig;
      getBackingTokens : () -> [BackingTypes.BackingPair];
      getTotalSupply : () -> Types.Amount;
      getSupplyUnit : () -> Nat;
      getMultiToken : () -> Types.Token;
    },
    virtualAccounts : {
      getBalance : (Types.Account, Types.Token) -> Types.Amount;
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
          let balance = virtualAccounts.getBalance(systemAccount, pair.token);
          {
            tokenInfo = { canisterId = pair.token };
            backingUnit = pair.backingUnit;
            reserveQuantity = balance.value;
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
          let balance = virtualAccounts.getBalance(systemAccount, pair.token);
          {
            tokenInfo = { canisterId = pair.token };
            backingUnit = pair.backingUnit;
            reserveQuantity = balance.value;
          };
        },
      );

      let totalSupply = backingStore.getTotalSupply();

      return #ok({
        initialized = true;
        totalSupply = totalSupply.value;
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
      let balance = virtualAccounts.getBalance(user, token);
      return #ok(balance.value);
    };

    public func getTotalSupplyResponse() : Messages.GetBalanceResponse {
      let supply = backingStore.getTotalSupply();
      return #ok(supply.value);
    };

    public func getMultiTokenBalanceResponse(user : Types.Account) : Messages.GetBalanceResponse {
      let multiToken = backingStore.getMultiToken();
      let balance = virtualAccounts.getBalance(user, multiToken);
      return #ok(balance.value);
    };
  };
};
