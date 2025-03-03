import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import Error "../error/Error";
import Text "mo:base/Text";
import SettingsTypes "../types/SettingsTypes";

module {

  // Validation helper function
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

  public class Settings(state : SettingsTypes.SettingsState) {
    // Token approval methods
    public func approveToken(token : Types.Token) : Result.Result<(), Error.ApprovalError> {
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

    public func isTokenApproved(token : Types.Token) : Bool {
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

    public func getApprovedTokens() : [Types.Token] {
      return state.approvedTokens;
    };

    public func getApprovedTokensCount() : Nat {
      return state.approvedTokens.size();
    };

    // Governance token methods
    public func setGovernanceToken(token : Types.Token) : Result.Result<(), Error.ApprovalError> {
      switch (validatePrincipal(token)) {
        case (#err(error)) {
          return #err(error);
        };
        case (#ok()) {};
      };

      state.governanceToken := ?token;
      return #ok(());
    };

    public func getGovernanceToken() : ?Types.Token {
      return state.governanceToken;
    };

    public func hasGovernanceToken() : Bool {
      return state.governanceToken != null;
    };

    // Use during system initialization
    public func clearSettings() {
      state.approvedTokens := [];
      state.governanceToken := null;
    };
  };
};
