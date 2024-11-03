import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Backing "./Backing";

/// Multi-token implementing ICRC1 and ICRC2 standards with configurable backing
shared ({ caller = deployer }) actor class MultiToken(
  initConfig : ?Backing.BackingConfig,
  args : ?{
    icrc1 : ?ICRC1.InitArgs;
    icrc2 : ?ICRC2.InitArgs;
  },
) = this {

  // -- State Variables --
  private var hasInitialized : Bool = false;
  private var backingTokens : [Backing.BackingPair] = [];
  stable var owner : Principal = deployer;
  private var canisterPrincipal_ : ?Principal = null;

  // -- Initialization --
  do {
    switch (initConfig) {
      case (null) {};
      case (?config) {
        switch (Backing.validateBackingConfig(config)) {
          case (#ok) {
            backingTokens := config.backingPairs;
            hasInitialized := true;
          };
          case (#err(e)) {
            Debug.print("Initial backing token configuration failed: " # e);
          };
        };
      };
    };
  };

  let defaultIcrc1Args : ICRC1.InitArgs = {
    name = ?"Multi Token";
    symbol = ?"MULTI";
    logo = ?"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==";
    decimals = 8;
    fee = ? #Fixed(10000);
    minting_account = ?{
      owner = deployer;
      subaccount = null;
    };
    max_supply = null;
    min_burn_amount = ?10000;
    max_memo = ?64;
    advanced_settings = null;
    metadata = null;
    fee_collector = null;
    transaction_window = null;
    permitted_drift = null;
    max_accounts = ?100000000;
    settle_to_accounts = ?99999000;
  };

  let defaultIcrc2Args : ICRC2.InitArgs = {
    max_approvals_per_account = ?10000;
    max_allowance = ? #TotalSupply;
    fee = ? #ICRC1;
    advanced_settings = null;
    max_approvals = ?10000000;
    settle_to_approvals = ?9990000;
  };

  let icrc1Args : ICRC1.InitArgs = switch (args) {
    case (null) defaultIcrc1Args;
    case (?args) {
      switch (args.icrc1) {
        case (null) defaultIcrc1Args;
        case (?val) {
          {
            val with minting_account = switch (val.minting_account) {
              case (?val) ?val;
              case (null) ?{
                owner = deployer;
                subaccount = null;
              };
            };
          };
        };
      };
    };
  };

  let icrc2Args : ICRC2.InitArgs = switch (args) {
    case (null) defaultIcrc2Args;
    case (?args) {
      switch (args.icrc2) {
        case (null) defaultIcrc2Args;
        case (?val) val;
      };
    };
  };

  stable let icrc1State = ICRC1.init(ICRC1.initialState(), #v0_1_0(#id), ?icrc1Args, deployer);
  stable let icrc2State = ICRC2.init(ICRC2.initialState(), #v0_1_0(#id), ?icrc2Args, deployer);

  // -- ICRC1 Setup --
  let #v0_1_0(#data(_)) = icrc1State;
  private var icrc1Instance_ : ?ICRC1.ICRC1 = null;

  private func getIcrc1Environment() : ICRC1.Environment {
    {
      get_time = null;
      get_fee = null;
      add_ledger_transaction = null;
      can_transfer = null;
    };
  };

  /// Returns or initializes ICRC1 instance
  private func getIcrc1() : ICRC1.ICRC1 {
    switch (icrc1Instance_) {
      case (null) {
        let instance = ICRC1.ICRC1(?icrc1State, Principal.fromActor(this), getIcrc1Environment());
        icrc1Instance_ := ?instance;
        canisterPrincipal_ := ?Principal.fromActor(this);
        instance;
      };
      case (?val) val;
    };
  };

  // -- ICRC2 Setup --
  let #v0_1_0(#data(_)) = icrc2State;
  private var icrc2Instance_ : ?ICRC2.ICRC2 = null;

  private func getIcrc2Environment() : ICRC2.Environment {
    {
      icrc1 = getIcrc1();
      get_fee = null;
      can_approve = null;
      can_transfer_from = null;
    };
  };

  /// Returns or initializes ICRC2 instance
  private func getIcrc2() : ICRC2.ICRC2 {
    switch (icrc2Instance_) {
      case (null) {
        let instance = ICRC2.ICRC2(?icrc2State, Principal.fromActor(this), getIcrc2Environment());
        icrc2Instance_ := ?instance;
        instance;
      };
      case (?val) val;
    };
  };

  /// Initialize token with backing configuration
  public shared ({ caller }) func initialize(config : Backing.BackingConfig) : async Result.Result<(), Text> {
    if (hasInitialized) {
      return #err("Already initialized");
    };

    switch (Backing.validateBackingConfig(config)) {
      case (#err(e)) { #err(e) };
      case (#ok()) {
        backingTokens := config.backingPairs;
        hasInitialized := true;
        #ok(());
      };
    };
  };

  // -- ICRC1 Interface --

  public shared query func icrc1_name() : async Text {
    getIcrc1().name();
  };

  public shared query func icrc1_symbol() : async Text {
    getIcrc1().symbol();
  };

  public shared query func icrc1_decimals() : async Nat8 {
    getIcrc1().decimals();
  };

  public shared query func icrc1_fee() : async ICRC1.Balance {
    getIcrc1().fee();
  };

  public shared query func icrc1_metadata() : async [ICRC1.MetaDatum] {
    getIcrc1().metadata();
  };

  public shared query func icrc1_total_supply() : async ICRC1.Balance {
    getIcrc1().total_supply();
  };

  public shared query func icrc1_minting_account() : async ?ICRC1.Account {
    ?getIcrc1().minting_account();
  };

  public shared query func icrc1_balance_of(args : ICRC1.Account) : async ICRC1.Balance {
    getIcrc1().balance_of(args);
  };

  public shared ({ caller }) func icrc1_transfer(args : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    switch (await* getIcrc1().transfer_tokens(caller, args, false, null)) {
      case (#trappable(val)) val;
      case (#awaited(val)) val;
      case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 1 }));
      case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 1 }));
    };
  };

  // -- ICRC2 Interface --

  public query func icrc2_allowance(args : ICRC2.AllowanceArgs) : async ICRC2.Allowance {
    getIcrc2().allowance(args.spender, args.account, false);
  };

  public shared ({ caller }) func icrc2_approve(args : ICRC2.ApproveArgs) : async ICRC2.ApproveResponse {
    switch (await* getIcrc2().approve_transfers(caller, args, false, null)) {
      case (#trappable(val)) val;
      case (#awaited(val)) val;
      case (#err(#trappable(err))) Debug.trap(err);
      case (#err(#awaited(err))) Debug.trap(err);
    };
  };

  public shared ({ caller }) func icrc2_transfer_from(args : ICRC2.TransferFromArgs) : async ICRC2.TransferFromResponse {
    try {
      switch (await* getIcrc2().transfer_tokens_from(caller, args, null)) {
        case (#trappable(val)) val;
        case (#awaited(val)) val;
        case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 1 }));
        case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 1 }));
      };
    } catch (e) {
      #Err(#GenericError({ message = Error.message(e); error_code = 2 }));
    };
  };

  // -- Private Helper Functions --

  /// Mint new tokens to specified account
  private func mintTokens(to : ICRC1.Account, amount : Nat) : async* ICRC1.TransferResult {
    if (not hasInitialized) {
      return #Err(#GenericError({ message = "Not initialized"; error_code = 1 }));
    };

    let supplyUnit = switch (initConfig) {
      case (null) {
        return #Err(#GenericError({ message = "No backing config"; error_code = 2 }));
      };
      case (?config) { config.supplyUnit };
    };

    if (amount % supplyUnit != 0) {
      return #Err(#GenericError({ message = "Amount must be multiple of supply unit"; error_code = 3 }));
    };

    switch (canisterPrincipal_) {
      case (null) {
        return #Err(#GenericError({ message = "Canister not initialized"; error_code = 4 }));
      };
      case (?principal) {
        switch (
          await* getIcrc1().mint_tokens(
            principal,
            {
              to = to;
              amount = amount;
              memo = null;
              created_at_time = null;
            },
          )
        ) {
          case (#trappable(val)) val;
          case (#awaited(val)) val;
          case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 5 }));
          case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 5 }));
        };
      };
    };
  };

  // -- Query Methods --

  /// Returns whether token is initialized
  public query func isInitialized() : async Bool {
    hasInitialized;
  };

  /// Returns list of backing tokens
  public query func getBackingTokens() : async [Backing.BackingPair] {
    backingTokens;
  };

  // -- Admin Functions --

  /// Update owner to new principal
  public shared ({ caller }) func updateOwner(newOwner : Principal) : async Bool {
    if (caller != owner) Debug.trap("Unauthorized");
    owner := newOwner;
    true;
  };
};
