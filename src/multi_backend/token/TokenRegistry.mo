import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/BackingTypes";

module {
  public type TokenRegistry = {
    var approvedTokens : [Types.TokenInfo];
  };

  public class TokenRegistryManager(state : TokenRegistry) {
    public func approve(token : Types.TokenInfo) : Result.Result<(), Text> {
      if (Principal.equal(token.canisterId, Principal.fromText(""))) {
        return #err("Invalid token principal");
      };

      switch (
        Array.find<Types.TokenInfo>(
          state.approvedTokens,
          func(t) = Principal.equal(t.canisterId, token.canisterId),
        )
      ) {
        case (?_) : return #err("Token already approved");
        case null : {
          state.approvedTokens := Array.append(state.approvedTokens, [token]);
          return #ok(());
        };
      };
    };

    public func isApproved(tokenId : Principal) : Bool {
      return Array.find<Types.TokenInfo>(
        state.approvedTokens,
        func(t) = Principal.equal(t.canisterId, tokenId),
      ) != null;
    };

    public func getApproved() : [Types.TokenInfo] {
      return state.approvedTokens;
    };

    public func size() : Nat {
      return state.approvedTokens.size();
    };
  };
};
