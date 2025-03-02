import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Types "../../multi_backend/types/Types";
import BackingTypes "../../multi_backend/types/BackingTypes";
import BackingStore "../../multi_backend/backing/BackingStore";

suite(
  "Backing Store",
  func() {
    let token1 : Types.Token = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let multiToken : Types.Token = Principal.fromText("qhbym-qaaaa-aaaaa-aaafq-cai");
    let govToken : Types.Token = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    let createStore = func() : BackingStore.BackingStore {
      let state : BackingTypes.BackingState = {
        var hasInitialized = false;
        var config = {
          supplyUnit = 0;
          totalSupply = 0;
          backingPairs = [];
          multiToken = Principal.fromText("aaaaa-aa");
          governanceToken = Principal.fromText("aaaaa-aa");
        };
      };
      BackingStore.BackingStore(state);
    };

    test(
      "stores backing token correctly",
      func() {
        let store = createStore();
        store.addBackingToken(token1);
        let tokens = store.getBackingTokens();
        assert tokens.size() == 1;
        assert Principal.equal(tokens[0].token, token1);
        assert tokens[0].backingUnit == 0;
      },
    );

    test(
      "initializes state correctly",
      func() {
        let store = createStore();
        store.initialize(100, multiToken, govToken);
        assert store.hasInitialized();
        assert store.getSupplyUnit() == 100;
        assert store.getTotalSupply() == 0;
        assert Principal.equal(store.getConfig().multiToken, multiToken);
        assert Principal.equal(store.getConfig().governanceToken, govToken);
      },
    );

    test(
      "updates backing tokens correctly",
      func() {
        let store = createStore();
        let newTokens = [{
          token = token1;
          backingUnit = 100;
        }];
        store.updateBackingTokens(newTokens);
        let tokens = store.getBackingTokens();
        assert tokens.size() == 1;
        assert Principal.equal(tokens[0].token, token1);
        assert tokens[0].backingUnit == 100;
      },
    );
  },
);
