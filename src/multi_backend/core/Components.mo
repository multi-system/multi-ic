import Principal "mo:base/Principal";
import VirtualAccounts "../custodial/VirtualAccounts";
import BackingStore "../backing/BackingStore";
import BackingOperations "../backing/BackingOperations";
import Settings "../core/Settings";
import CustodialManager "../custodial/CustodialManager";
import RequestHandler "../api/RequestHandler";
import ResponseHandler "../api/ResponseHandler";
import BackingTypes "../types/BackingTypes";
import SettingsTypes "../types/SettingsTypes";
import Types "../types/Types";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import AccountTypes "../types/AccountTypes";

module {
  public class Components(
    settingsState : SettingsTypes.SettingsState,
    accountsState : StableHashMap.StableHashMap<Principal, AccountTypes.BalanceMap>,
    backingState : BackingTypes.BackingState,
  ) {
    private let settings = Settings.Settings(settingsState);
    private let virtualAccounts = VirtualAccounts.VirtualAccounts(accountsState);
    private let backingStore = BackingStore.BackingStore(backingState);

    private var backingOperations_ : ?BackingOperations.BackingOperations = null;
    private var custodialManager_ : ?CustodialManager.CustodialManager = null;
    private var requestHandler_ : ?RequestHandler.RequestHandler = null;
    private var responseHandler_ : ?ResponseHandler.ResponseHandler = null;

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
            settings,
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
            settings,
          );
          requestHandler_ := ?instance;
          return instance;
        };
        case (?val) {
          return val;
        };
      };
    };

    public func getResponseHandler(canisterId : Principal) : ResponseHandler.ResponseHandler {
      switch (responseHandler_) {
        case (null) {
          let instance = ResponseHandler.ResponseHandler(
            backingStore,
            virtualAccounts,
            canisterId,
            settings,
          );
          responseHandler_ := ?instance;
          return instance;
        };
        case (?val) {
          return val;
        };
      };
    };

    public func getSettings() : Settings.Settings {
      settings;
    };

    public func getVirtualAccounts() : VirtualAccounts.VirtualAccounts {
      virtualAccounts;
    };

    public func getBackingStore() : BackingStore.BackingStore {
      backingStore;
    };
  };
};
