import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import Error "../error/Error";
import Text "mo:base/Text";

module {
  public type TokenRegistry = {
    var approvedTokens : [Types.Token];
  };

  public func validatePrincipal(id : Principal) : Result.Result<(), Error.ApprovalError> {
    let principalText = Principal.toText(id);
    if (Principal.equal(id, Principal.fromText("aaaaa-aa"))) {
      return #err(#InvalidPrincipal({ principal = id; reason = "Cannot use default/empty principal ID" }));
    };
    if (Text.size(principalText) < 10) {
      return #err(#InvalidPrincipal({ principal = id; reason = "Principal ID is too short or malformed" }));
    };
    return #ok();
  };

  public class TokenRegistryManager(state : TokenRegistry) {
    public func approve(token : Types.Token) : Result.Result<(), Error.ApprovalError> {
      switch (validatePrincipal(token)) {
        case (#err(error)) {
          return #err(error);
        };
        case (#ok()) {};
      };

      switch (
        Array.find<Types.Token>(
          state.approvedTokens,
          func(t) = Principal.equal(t, token),
        )
      ) {
        case (?_) {
          return #err(#TokenAlreadyApproved(token));
        };
        case null {
          state.approvedTokens := Array.append(state.approvedTokens, [token]);
          return #ok(());
        };
      };
    };

    public func isApproved(token : Types.Token) : Bool {
      switch (validatePrincipal(token)) {
        case (#err(_)) {
          return false;
        };
        case (#ok()) {};
      };

      return Array.find<Types.Token>(
        state.approvedTokens,
        func(t) = Principal.equal(t, token),
      ) != null;
    };

    public func getApproved() : [Types.Token] {
      return state.approvedTokens;
    };

    public func size() : Nat {
      return state.approvedTokens.size();
    };
  };
};
