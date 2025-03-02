import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Debug "mo:base/Debug";
import Types "../types/BackingTypes";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingStore "../backing/BackingStore";
import BackingOperations "../backing/BackingOperations";
import TokenRegistry "../token/TokenRegistry";
import CustodialManager "../custodial/CustodialManager";
import Messages "./Messages";
import Error "../error/Error";
import ErrorMapping "../error/ErrorMapping";
import BackingApiHelper "./BackingApiHelper";

shared ({ caller = deployer }) actor class BackingApi() = this {
  //
  // STATE VARIABLES
  //
  private stable let owner : Principal = deployer;
  private stable var approvedTokens : [Types.TokenInfo] = [];

  private stable var backingState : Types.BackingState = {
    var hasInitialized = false;
    var config = {
      supplyUnit = 0;
      totalSupply = 0;
      backingPairs = [];
      multiToken = { canisterId = Principal.fromText("aaaaa-aa") };
      governanceToken = { canisterId = Principal.fromText("aaaaa-aa") };
    };
  };

  private stable var accountsState = StableHashMap.init<Principal, VirtualAccounts.BalanceMap>();

  //
  // COMPONENT INITIALIZATION
  //
  private let tokenRegistry = TokenRegistry.TokenRegistryManager({
    var approvedTokens = approvedTokens;
  });

  private let virtualAccounts = VirtualAccounts.VirtualAccountManager(accountsState);
  private let backingStore = BackingStore.BackingStore(backingState);

  // Initialize services lazily
  private var backingImpl_ : ?BackingOperations.BackingOperationsImpl = null;
  private func getBackingImpl() : BackingOperations.BackingOperationsImpl {
    switch (backingImpl_) {
      case (null) {
        let instance = BackingOperations.BackingOperationsImpl(
          backingStore,
          virtualAccounts,
          Principal.fromActor(this),
        );
        backingImpl_ := ?instance;
        return instance;
      };
      case (?val) {
        return val;
      };
    };
  };

  private var custodialManager_ : ?CustodialManager.CustodialManager = null;
  private func getCustodialManager() : CustodialManager.CustodialManager {
    switch (custodialManager_) {
      case (null) {
        let instance = CustodialManager.CustodialManager(
          tokenRegistry,
          virtualAccounts,
          Principal.fromActor(this),
        );
        custodialManager_ := ?instance;
        return instance;
      };
      case (?val) {
        return val;
      };
    };
  };

  private var apiHelper_ : ?BackingApiHelper.ApiHelper = null;
  private func getApiHelper() : BackingApiHelper.ApiHelper {
    switch (apiHelper_) {
      case (null) {
        let instance = BackingApiHelper.ApiHelper(
          backingStore,
          tokenRegistry,
          virtualAccounts,
          Principal.fromActor(this),
        );
        apiHelper_ := ?instance;
        return instance;
      };
      case (?val) {
        return val;
      };
    };
  };

  //
  // SYSTEM MANAGEMENT (ADMIN FUNCTIONS)
  //
  public shared ({ caller }) func approveToken(request : Messages.ApproveTokenRequest) : async Messages.ApproveTokenResponse {
    // Use the API helper for token approval with explicit type annotation
    let result : Result.Result<(), Error.ApprovalError> = await* getApiHelper().approveToken(
      caller,
      owner,
      { canisterId = request.canisterId },
      func(p : Principal) : async* Result.Result<(), Error.ApprovalError> {
        return await* getCustodialManager().addLedger(p);
      },
    );

    return ErrorMapping.mapDirectApprovalResult(result);
  };

  public shared ({ caller }) func initialize(request : Messages.InitializeRequest) : async Messages.InitializeResponse {
    // Use the API helper for initialization
    switch (
      getApiHelper().initialize(
        caller,
        owner,
        request,
        getBackingImpl().processInitialize,
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
    switch (getApiHelper().validateDepositPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (await* getCustodialManager().deposit(caller, request.token, request.amount)) {
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
    switch (getApiHelper().validateWithdrawPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (await* getCustodialManager().withdraw(caller, request.token, request.amount)) {
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
    switch (getApiHelper().validateIssuePreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (getBackingImpl().processIssue(caller, request.amount)) {
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
    switch (getApiHelper().validateRedeemPreconditions(caller)) {
      case (?error) return #err(error);
      case (null) {};
    };

    // Proceed with operation
    switch (getBackingImpl().processRedeem(caller, request.amount)) {
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
    backingStore.hasInitialized();
  };

  public query func getBackingTokens() : async Messages.GetTokensResponse {
    return getApiHelper().formatBackingTokensResponse();
  };

  public query func getVirtualBalance(user : Principal, token : Principal) : async Messages.GetBalanceResponse {
    return getApiHelper().getBalanceResponse(user, token);
  };

  public query func getTotalSupply() : async Messages.GetBalanceResponse {
    return getApiHelper().getTotalSupplyResponse();
  };

  public query func getMultiTokenBalance(user : Principal) : async Messages.GetBalanceResponse {
    return getApiHelper().getMultiTokenBalanceResponse(user);
  };

  public query func getMultiTokenId() : async Principal {
    backingStore.getConfig().multiToken.canisterId;
  };

  public query func getGovernanceTokenId() : async Principal {
    backingStore.getConfig().governanceToken.canisterId;
  };

  public query func getSystemInfo() : async Messages.GetSystemInfoResponse {
    return getApiHelper().formatSystemInfoResponse();
  };
};
