import Principal "mo:base/Principal";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingStore "../backing/BackingStore";
import BackingOperations "../backing/BackingOperations";
import TokenRegistry "../token/TokenRegistry";
import CustodialManager "../custodial/CustodialManager";
import RequestHandler "../api/RequestHandler";
import BackingTypes "../types/BackingTypes";
import Types "../types/Types";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../types/AccountTypes";

module {
  public class Components(
    tokenRegistryState : { var approvedTokens : [Types.Token] },
    accountsState : StableHashMap.StableHashMap<Principal, AccountTypes.BalanceMap>,
    backingState : BackingTypes.BackingState,
  ) {
    // Initialize core components that don't need the canister ID
    private let tokenRegistry = TokenRegistry.TokenRegistryManager(tokenRegistryState);
    private let virtualAccounts = VirtualAccounts.VirtualAccounts(accountsState);
    private let backingStore = BackingStore.BackingStore(backingState);

    // Lazy component initialization
    private var backingOperations_ : ?BackingOperations.BackingOperations = null;
    private var custodialManager_ : ?CustodialManager.CustodialManager = null;
    private var requestHandler_ : ?RequestHandler.RequestHandler = null;

    public func getBackingOperations(canisterId : Principal) : BackingOperations.BackingOperations {
      switch (backingOperations_) {
        case (null) {
          let instance = BackingOperations.BackingOperations(
            backingStore,
            virtualAccounts,
            canisterId,
          );
          backingOperations_ := ?instance;
          return instance;
        };
        case (?val) {
          return val;
        };
      };
    };

    public func getCustodialManager(canisterId : Principal) : CustodialManager.CustodialManager {
      switch (custodialManager_) {
        case (null) {
          let instance = CustodialManager.CustodialManager(
            tokenRegistry,
            virtualAccounts,
            canisterId,
          );
          custodialManager_ := ?instance;
          return instance;
        };
        case (?val) {
          return val;
        };
      };
    };

    public func getRequestHandler(canisterId : Principal) : RequestHandler.RequestHandler {
      switch (requestHandler_) {
        case (null) {
          let instance = RequestHandler.RequestHandler(
            backingStore,
            tokenRegistry,
            virtualAccounts,
            canisterId,
          );
          requestHandler_ := ?instance;
          return instance;
        };
        case (?val) {
          return val;
        };
      };
    };

    // Expose internal component getters
    public func getTokenRegistry() : TokenRegistry.TokenRegistryManager {
      tokenRegistry;
    };

    public func getVirtualAccounts() : VirtualAccounts.VirtualAccounts {
      virtualAccounts;
    };

    public func getBackingStore() : BackingStore.BackingStore {
      backingStore;
    };
  };
};
