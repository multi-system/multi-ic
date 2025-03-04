import Principal "mo:base/Principal";
import Result "mo:base/Result";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import SettingsTypes "../types/SettingsTypes";
import Messages "./Messages";
import Error "../error/Error";
import ErrorMapping "../error/ErrorMapping";
import Components "../core/Components";
import AccountTypes "../types/AccountTypes";
import AmountOperations "../financial/AmountOperations";

shared ({ caller = deployer }) actor class MultiBackend() = this {
  private stable let owner : Types.Account = deployer;

  private stable var settingsState : SettingsTypes.SettingsState = {
    var approvedTokens = [];
    var governanceToken = null;
  };

  private stable var backingState : BackingTypes.BackingState = {
    var hasInitialized = false;
    var config = {
      supplyUnit = 0;
      totalSupply = 0;
      backingPairs = [];
      multiToken = Principal.fromText("aaaaa-aa");
    };
  };

  private stable var accountsState = StableHashMap.init<Principal, AccountTypes.BalanceMap>();

  private let c = Components.Components(
    settingsState,
    accountsState,
    backingState,
  );

  public shared ({ caller }) func approveToken(request : Messages.ApproveTokenRequest) : async Messages.ApproveTokenResponse {
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
    switch (
      c.getRequestHandler(Principal.fromActor(this)).initialize(
        caller,
        owner,
        request,
        func(backingPairs : [BackingTypes.BackingPair], supplyUnit : Nat, multiToken : Types.Token) : Result.Result<(), Error.InitError> {
          return c.getBackingOperations(Principal.fromActor(this)).processInitialize(backingPairs, supplyUnit, multiToken);
        },
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

  public shared ({ caller }) func deposit(request : Messages.DepositRequest) : async Messages.DepositResponse {
    switch (c.getRequestHandler(Principal.fromActor(this)).validateDepositPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    let amount = AmountOperations.new(request.token, request.amount);

    switch (await* c.getCustodialManager(Principal.fromActor(this)).deposit(caller, amount)) {
      case (#err(e)) {
        return ErrorMapping.mapToDepositResponse(e);
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func withdraw(request : Messages.WithdrawRequest) : async Messages.WithdrawResponse {
    switch (c.getRequestHandler(Principal.fromActor(this)).validateWithdrawPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    let amount = AmountOperations.new(request.token, request.amount);

    switch (await* c.getCustodialManager(Principal.fromActor(this)).withdraw(caller, amount)) {
      case (#err(e)) {
        return ErrorMapping.mapToWithdrawResponse(e);
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func issue(request : Messages.IssueRequest) : async Messages.IssueResponse {
    switch (c.getRequestHandler(Principal.fromActor(this)).validateIssuePreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    let multiToken = c.getBackingStore().getMultiToken();
    let amount = AmountOperations.new(multiToken, request.amount);

    switch (c.getBackingOperations(Principal.fromActor(this)).processIssue(caller, amount)) {
      case (#err(e)) {
        return #err(ErrorMapping.mapOperationError(e));
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

  public shared ({ caller }) func redeem(request : Messages.RedeemRequest) : async Messages.RedeemResponse {
    switch (c.getRequestHandler(Principal.fromActor(this)).validateRedeemPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    let multiToken = c.getBackingStore().getMultiToken();
    let amount = AmountOperations.new(multiToken, request.amount);

    switch (c.getBackingOperations(Principal.fromActor(this)).processRedeem(caller, amount)) {
      case (#err(e)) {
        return #err(ErrorMapping.mapOperationError(e));
      };
      case (#ok()) {
        return #ok(());
      };
    };
  };

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
    c.getBackingStore().getMultiToken();
  };

  public query func getGovernanceTokenId() : async Principal {
    switch (c.getSettings().getGovernanceToken()) {
      case (?token) { token };
      case (null) { Principal.fromText("aaaaa-aa") };
    };
  };

  public query func getSystemInfo() : async Messages.GetSystemInfoResponse {
    return c.getResponseHandler(Principal.fromActor(this)).formatSystemInfoResponse();
  };
};
