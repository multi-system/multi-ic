import Principal "mo:base/Principal";
import Result "mo:base/Result";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Messages "./Messages";
import Error "../error/Error";
import ErrorMapping "../error/ErrorMapping";
import Components "../core/Components";
import AccountTypes "../types/AccountTypes";

shared ({ caller = deployer }) actor class MultiBackend() = this {
  //
  // STATE VARIABLES
  //
  private stable let owner : Types.Account = deployer;
  private stable var approvedTokens : [Types.Token] = [];

  private stable var backingState : BackingTypes.BackingState = {
    var hasInitialized = false;
    var config = {
      supplyUnit = 0;
      totalSupply = 0;
      backingPairs = [];
      multiToken = Principal.fromText("aaaaa-aa");
      governanceToken = Principal.fromText("aaaaa-aa");
    };
  };

  private stable var accountsState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();

  //
  // COMPONENT INITIALIZATION
  //
  private let c = Components.Components(
    { var approvedTokens = approvedTokens },
    accountsState,
    backingState,
  );

  //
  // SYSTEM MANAGEMENT (ADMIN FUNCTIONS)
  //
  public shared ({ caller }) func approveToken(request : Messages.ApproveTokenRequest) : async Messages.ApproveTokenResponse {
    // Use the API helper for token approval with explicit type annotation
    let result : Result.Result<(), Error.ApprovalError> = await* c.getRequestHandler(Principal.fromActor(this)).approveToken(
      caller,
      owner,
      { canisterId = request.canisterId },
      func(p : Types.Token) : async* Result.Result<(), Error.ApprovalError> {
        return await* c.getCustodialManager(Principal.fromActor(this)).addLedger(p);
      },
    );

    return ErrorMapping.mapDirectApprovalResult(result);
  };

  public shared ({ caller }) func initialize(request : Messages.InitializeRequest) : async Messages.InitializeResponse {
    // Use the API helper for initialization
    switch (
      c.getRequestHandler(Principal.fromActor(this)).initialize(
        caller,
        owner,
        request,
        c.getBackingOperations(Principal.fromActor(this)).processInitialize,
      )
    ) {
      case (#err(e)) {
        return #err(ErrorMapping.mapInitError(e));
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  //
  // USER OPERATIONS (UPDATE METHODS)
  //
  public shared ({ caller }) func deposit(request : Messages.DepositRequest) : async Messages.DepositResponse {
    // Validate preconditions
    switch (c.getRequestHandler(Principal.fromActor(this)).validateDepositPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (await* c.getCustodialManager(Principal.fromActor(this)).deposit(caller, request.token, request.amount)) {
      case (#err(e)) {
        return ErrorMapping.mapToDepositResponse(e);
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func withdraw(request : Messages.WithdrawRequest) : async Messages.WithdrawResponse {
    // Validate preconditions
    switch (c.getRequestHandler(Principal.fromActor(this)).validateWithdrawPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (await* c.getCustodialManager(Principal.fromActor(this)).withdraw(caller, request.token, request.amount)) {
      case (#err(e)) {
        return ErrorMapping.mapToWithdrawResponse(e);
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func issue(request : Messages.IssueRequest) : async Messages.IssueResponse {
    // Validate preconditions
    switch (c.getRequestHandler(Principal.fromActor(this)).validateIssuePreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (c.getBackingOperations(Principal.fromActor(this)).processIssue(caller, request.amount)) {
      case (#err(e)) {
        return #err(ErrorMapping.mapOperationError(e));
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func redeem(request : Messages.RedeemRequest) : async Messages.RedeemResponse {
    // Validate preconditions
    switch (c.getRequestHandler(Principal.fromActor(this)).validateRedeemPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (c.getBackingOperations(Principal.fromActor(this)).processRedeem(caller, request.amount)) {
      case (#err(e)) {
        return #err(ErrorMapping.mapOperationError(e));
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  //
  // QUERY METHODS (READ-ONLY)
  //
  public query func isInitialized() : async Bool {
    c.getBackingStore().hasInitialized();
  };

  public query func getBackingTokens() : async Messages.GetTokensResponse {
    return c.getResponseHandler(Principal.fromActor(this)).formatBackingTokensResponse();
  };

  public query func getVirtualBalance(user : Principal, token : Principal) : async Messages.GetBalanceResponse {
    return c.getResponseHandler(Principal.fromActor(this)).getBalanceResponse(user, token);
  };

  public query func getTotalSupply() : async Messages.GetBalanceResponse {
    return c.getResponseHandler(Principal.fromActor(this)).getTotalSupplyResponse();
  };

  public query func getMultiTokenBalance(user : Principal) : async Messages.GetBalanceResponse {
    return c.getResponseHandler(Principal.fromActor(this)).getMultiTokenBalanceResponse(user);
  };

  public query func getMultiTokenId() : async Principal {
    c.getBackingStore().getConfig().multiToken;
  };

  public query func getGovernanceTokenId() : async Principal {
    c.getBackingStore().getConfig().governanceToken;
  };

  public query func getSystemInfo() : async Messages.GetSystemInfoResponse {
    return c.getResponseHandler(Principal.fromActor(this)).formatSystemInfoResponse();
  };
};
