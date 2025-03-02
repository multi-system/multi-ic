import Principal "mo:base/Principal";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingStore "../backing/BackingStore";
import BackingOperations "../backing/BackingOperations";
import TokenRegistry "../token/TokenRegistry";
import CustodialManager "../custodial/CustodialManager";
import BackingApiHelper "../api/BackingApiHelper";
import BackingTypes "../types/BackingTypes";
import Types "../types/Types";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

module {
  public class ComponentManager(
    tokenRegistryState : { var approvedTokens : [Types.Token] },
    accountsState : StableHashMap.StableHashMap<Principal, VirtualAccounts.BalanceMap>,
    backingState : BackingTypes.BackingState,
  ) {
    // Initialize core components that don't need the canister ID
    private let tokenRegistry = TokenRegistry.TokenRegistryManager(tokenRegistryState);
    private let virtualAccounts = VirtualAccounts.VirtualAccountManager(accountsState);
    private let backingStore = BackingStore.BackingStore(backingState);

    // Lazy component initialization
    private var backingImpl_ : ?BackingOperations.BackingOperationsImpl = null;
    private var custodialManager_ : ?CustodialManager.CustodialManager = null;
    private var apiHelper_ : ?BackingApiHelper.ApiHelper = null;

    public func getBackingImpl(canisterId : Principal) : BackingOperations.BackingOperationsImpl {
      switch (backingImpl_) {
        case (null) {
          let instance = BackingOperations.BackingOperationsImpl(
            backingStore,
            virtualAccounts,
            canisterId,
          );
          backingImpl_ := ?instance;
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

    public func getApiHelper(canisterId : Principal) : BackingApiHelper.ApiHelper {
      switch (apiHelper_) {
        case (null) {
          let instance = BackingApiHelper.ApiHelper(
            backingStore,
            tokenRegistry,
            virtualAccounts,
            canisterId,
          );
          apiHelper_ := ?instance;
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

    public func getVirtualAccounts() : VirtualAccounts.VirtualAccountManager {
      virtualAccounts;
    };

    public func getBackingStore() : BackingStore.BackingStore {
      backingStore;
    };
  };
};
