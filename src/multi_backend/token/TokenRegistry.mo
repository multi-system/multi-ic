import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/BackingTypes";
import Error "../error/Error";
import Text "mo:base/Text";

module {
  public type TokenRegistry = {
    var approvedTokens : [Types.TokenInfo];
  };

  public func validatePrincipal(id : Principal) : Result.Result<(), { principal : Principal; reason : Text }> {
    let principalText = Principal.toText(id);

    if (Principal.equal(id, Principal.fromText("aaaaa-aa"))) {
      return #err({
        principal = id;
        reason = "Cannot use default/empty principal ID";
      });
    };

    if (Text.size(principalText) < 10) {
      return #err({
        principal = id;
        reason = "Principal ID is too short or malformed";
      });
    };

    return #ok();
  };

  public class TokenRegistryManager(state : TokenRegistry) {
    public func approve(token : Types.TokenInfo) : Result.Result<(), Error.ApprovalError> {
      switch (validatePrincipal(token.canisterId)) {
        case (#err(details)) {
          return #err(#InvalidPrincipal(details));
        };
        case (#ok()) {};
      };

      switch (
        Array.find<Types.TokenInfo>(
          state.approvedTokens,
          func(t) = Principal.equal(t.canisterId, token.canisterId),
        )
      ) {
        case (?_) {
          return #err(#TokenAlreadyApproved(token.canisterId));
        };
        case null {
          state.approvedTokens := Array.append(state.approvedTokens, [token]);
          return #ok(());
        };
      };
    };

    public func isApproved(tokenId : Principal) : Bool {
      switch (validatePrincipal(tokenId)) {
        case (#err(_)) {
          return false;
        };
        case (#ok()) {};
      };

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
