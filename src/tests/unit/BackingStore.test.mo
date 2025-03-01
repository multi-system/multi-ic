import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/BackingTypes";
import BackingStore "../../multi_backend/backing/BackingStore";

suite(
  "Backing Store",
  func() {
    let token1Principal = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let multiTokenPrincipal = Principal.fromText("qhbym-qaaaa-aaaaa-aaafq-cai");
    let govTokenPrincipal = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    let token1Info : Types.TokenInfo = { canisterId = token1Principal };
    let multiTokenInfo : Types.TokenInfo = { canisterId = multiTokenPrincipal };
    let govTokenInfo : Types.TokenInfo = { canisterId = govTokenPrincipal };

    let createStore = func() : BackingStore.BackingStore {
      let state : Types.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 0;
          totalSupply = 0;
          backingPairs = [];
          multiToken = { canisterId = Principal.fromText("aaaaa-aa") };
          governanceToken = { canisterId = Principal.fromText("aaaaa-aa") };
        };
      };
      BackingStore.BackingStore(state);
    };

    test(
      "stores backing token correctly",
      func() {
        let store = createStore();
        store.addBackingToken(token1Info);
        let tokens = store.getBackingTokens();
        assert tokens.size() == 1;
        assert Principal.equal(tokens[0].tokenInfo.canisterId, token1Principal);
        assert tokens[0].backingUnit == 0;
      },
    );

    test(
      "initializes state correctly",
      func() {
        let store = createStore();
        store.initialize(100, multiTokenInfo, govTokenInfo);
        assert store.hasInitialized();
        assert store.getSupplyUnit() == 100;
        assert store.getTotalSupply() == 0;
        assert Principal.equal(store.getConfig().multiToken.canisterId, multiTokenPrincipal);
        assert Principal.equal(store.getConfig().governanceToken.canisterId, govTokenPrincipal);
      },
    );

    test(
      "updates backing tokens correctly",
      func() {
        let store = createStore();
        let newTokens = [{
          tokenInfo = token1Info;
          backingUnit = 100;
        }];
        store.updateBackingTokens(newTokens);
        let tokens = store.getBackingTokens();
        assert tokens.size() == 1;
        assert Principal.equal(tokens[0].tokenInfo.canisterId, token1Principal);
        assert tokens[0].backingUnit == 100;
      },
    );
  },
);
