import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Result "mo:base/Result";
import Error "mo:base/Error";
import TokenBacking "./token_backing";

shared ({ caller = deployer }) actor class MultiToken(
  init_config : ?TokenBacking.BackingConfig,
  args : ?{
    icrc1 : ?ICRC1.InitArgs;
    icrc2 : ?ICRC2.InitArgs;
  },
) = this {

  // Backing token state
  private var initialized : Bool = false;
  private var backingTokens : [TokenBacking.BackingPair] = [];
  stable var owner : Principal = deployer;

  // Initialize backing tokens if provided in constructor
  do {
    switch (init_config) {
      case (null) {};
      case (?config) {
        switch (TokenBacking.validateBackingConfig(config)) {
          case (#ok) {
            backingTokens := config.backing_pairs;
            initialized := true;
          };
          case (#err(e)) {
            Debug.print("Initial backing token configuration failed: " # e);
          };
        };
      };
    };
  };

  let default_icrc1_args : ICRC1.InitArgs = {
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

  let default_icrc2_args : ICRC2.InitArgs = {
    max_approvals_per_account = ?10000;
    max_allowance = ? #TotalSupply;
    fee = ? #ICRC1;
    advanced_settings = null;
    max_approvals = ?10000000;
    settle_to_approvals = ?9990000;
  };

  let icrc1_args : ICRC1.InitArgs = switch (args) {
    case (null) default_icrc1_args;
    case (?args) {
      switch (args.icrc1) {
        case (null) default_icrc1_args;
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

  let icrc2_args : ICRC2.InitArgs = switch (args) {
    case (null) default_icrc2_args;
    case (?args) {
      switch (args.icrc2) {
        case (null) default_icrc2_args;
        case (?val) val;
      };
    };
  };

  stable let icrc1_migration_state = ICRC1.init(ICRC1.initialState(), #v0_1_0(#id), ?icrc1_args, deployer);
  stable let icrc2_migration_state = ICRC2.init(ICRC2.initialState(), #v0_1_0(#id), ?icrc2_args, deployer);

  let #v0_1_0(#data(_)) = icrc1_migration_state;
  private var _icrc1 : ?ICRC1.ICRC1 = null;

  private func get_icrc1_environment() : ICRC1.Environment {
    {
      get_time = null;
      get_fee = null;
      add_ledger_transaction = null;
      can_transfer = null;
    };
  };

  func icrc1() : ICRC1.ICRC1 {
    switch (_icrc1) {
      case (null) {
        let initclass = ICRC1.ICRC1(?icrc1_migration_state, Principal.fromActor(this), get_icrc1_environment());
        _icrc1 := ?initclass;
        initclass;
      };
      case (?val) val;
    };
  };

  let #v0_1_0(#data(_)) = icrc2_migration_state;
  private var _icrc2 : ?ICRC2.ICRC2 = null;

  private func get_icrc2_environment() : ICRC2.Environment {
    {
      icrc1 = icrc1();
      get_fee = null;
      can_approve = null;
      can_transfer_from = null;
    };
  };

  func icrc2() : ICRC2.ICRC2 {
    switch (_icrc2) {
      case (null) {
        let initclass = ICRC2.ICRC2(?icrc2_migration_state, Principal.fromActor(this), get_icrc2_environment());
        _icrc2 := ?initclass;
        initclass;
      };
      case (?val) val;
    };
  };

  public shared ({ caller }) func initialize(config : TokenBacking.BackingConfig) : async Result.Result<(), Text> {
    // Check initialization state first
    if (initialized) {
      return #err("Already initialized");
    };

    // Then validate config without checking reserves
    switch (TokenBacking.validateBackingConfig(config)) {
      case (#err(e)) { return #err(e) };
      case (#ok()) {
        backingTokens := config.backing_pairs;
        initialized := true;
        #ok(());
      };
    };
  };

  // ICRC1 Interface
  public shared query func icrc1_name() : async Text {
    icrc1().name();
  };

  public shared query func icrc1_symbol() : async Text {
    icrc1().symbol();
  };

  public shared query func icrc1_decimals() : async Nat8 {
    icrc1().decimals();
  };

  public shared query func icrc1_fee() : async ICRC1.Balance {
    icrc1().fee();
  };

  public shared query func icrc1_metadata() : async [ICRC1.MetaDatum] {
    icrc1().metadata();
  };

  public shared query func icrc1_total_supply() : async ICRC1.Balance {
    icrc1().total_supply();
  };

  public shared query func icrc1_minting_account() : async ?ICRC1.Account {
    ?icrc1().minting_account();
  };

  public shared query func icrc1_balance_of(args : ICRC1.Account) : async ICRC1.Balance {
    icrc1().balance_of(args);
  };

  public shared ({ caller }) func icrc1_transfer(args : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    switch (await* icrc1().transfer_tokens(caller, args, false, null)) {
      case (#trappable(val)) val;
      case (#awaited(val)) val;
      case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 1 }));
      case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 1 }));
    };
  };

  // ICRC2 Interface
  public query func icrc2_allowance(args : ICRC2.AllowanceArgs) : async ICRC2.Allowance {
    icrc2().allowance(args.spender, args.account, false);
  };

  public shared ({ caller }) func icrc2_approve(args : ICRC2.ApproveArgs) : async ICRC2.ApproveResponse {
    switch (await* icrc2().approve_transfers(caller, args, false, null)) {
      case (#trappable(val)) val;
      case (#awaited(val)) val;
      case (#err(#trappable(err))) Debug.trap(err);
      case (#err(#awaited(err))) Debug.trap(err);
    };
  };

  public shared ({ caller }) func icrc2_transfer_from(args : ICRC2.TransferFromArgs) : async ICRC2.TransferFromResponse {
    try {
      switch (await* icrc2().transfer_tokens_from(caller, args, null)) {
        case (#trappable(val)) val;
        case (#awaited(val)) val;
        case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 1 }));
        case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 1 }));
      };
    } catch (e) {
      #Err(#GenericError({ message = Error.message(e); error_code = 2 }));
    };
  };

  // Query methods
  public query func is_initialized() : async Bool {
    initialized;
  };

  public query func get_backing_tokens() : async [TokenBacking.BackingPair] {
    backingTokens;
  };

  // Admin functions
  public shared ({ caller }) func admin_update_owner(new_owner : Principal) : async Bool {
    if (caller != owner) Debug.trap("Unauthorized");
    owner := new_owner;
    true;
  };
};
