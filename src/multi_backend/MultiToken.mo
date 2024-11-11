import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Backing "./Backing";
import Messages "./Messages";
import ICRC2_Types "mo:icrc2-types";

shared ({ caller = deployer }) actor class MultiToken(
  args : ?{
    icrc1 : ?ICRC1.InitArgs;
    icrc2 : ?ICRC2.InitArgs;
  }
) = this {

  // -- State Variables --
  private var hasInitialized : Bool = false;
  private var backingTokens : [var Backing.BackingPair] = [var];
  private var supplyUnit : Nat = 0;
  private var totalSupply : Nat = 0;
  stable var owner : Principal = deployer;

  let defaultIcrc1Args : ICRC1.InitArgs = {
    name = ?"Multi Token";
    symbol = ?"MULTI";
    logo = ?"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==";
    decimals = 8;
    fee = ? #Fixed(10000);
    minting_account = ?{
      owner = deployer; // We'll keep deployer as minting account initially
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
          // Keep other values from val but ensure minting_account is deployer
          {
            val with minting_account = ?{
              owner = deployer;
              subaccount = null;
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

  private func getIcrc1() : ICRC1.ICRC1 {
    switch (icrc1Instance_) {
      case (null) {
        let instance = ICRC1.ICRC1(?icrc1State, Principal.fromActor(this), getIcrc1Environment());
        icrc1Instance_ := ?instance;
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
  public shared ({ caller }) func initialize(msg : Messages.InitializeMsg) : async Result.Result<(), Text> {
    if (hasInitialized) {
      return #err("Already initialized");
    };

    // Convert message format to internal config
    let internalConfig : Backing.BackingConfig = {
      supplyUnit = msg.supplyUnit;
      totalSupply = 0;
      backingPairs = Array.map<Messages.TokenConfig, Backing.BackingPair>(
        msg.backingTokens,
        func(tc : Messages.TokenConfig) : Backing.BackingPair {
          {
            tokenInfo = {
              canisterId = tc.canisterId;
              token = actor (Principal.toText(tc.canisterId)) : ICRC2_Types.Service;
            };
            backingUnit = tc.backingUnit;
            reserveQuantity = 0;
          };
        },
      );
    };

    switch (await* Backing.validateBackingFull(internalConfig)) {
      case (#err(e)) { return #err(e) };
      case (#ok()) {
        backingTokens := Array.thaw(internalConfig.backingPairs);
        supplyUnit := internalConfig.supplyUnit;
        hasInitialized := true;

        // After initialization, update the minting account to this canister
        // We'll do this through the update_ledger_info function which is part of ICRC1
        ignore getIcrc1().update_ledger_info([
          #MintingAccount({
            owner = Principal.fromActor(this);
            subaccount = null;
          })
        ]);

        #ok(());
      };
    };
  };

  // -- Public Token Operations --

  /// Issue new tokens by providing backing tokens
  public shared ({ caller }) func issue(args : Messages.IssueArgs) : async Messages.IssueResponse {
    Debug.print("=== Issue Operation Started ===");
    Debug.print("Caller: " # debug_show (caller));
    Debug.print("Amount: " # debug_show (args.amount));
    Debug.print("Current total supply: " # debug_show (totalSupply));
    Debug.print("Supply unit: " # debug_show (supplyUnit));

    if (not hasInitialized) {
      Debug.print("Issue failed: not initialized");
      return #NotInitialized;
    };

    switch (
      await* Backing.processIssue(
        args.amount,
        supplyUnit,
        totalSupply,
        caller,
        Principal.fromActor(this),
        backingTokens,
      )
    ) {
      case (#err(e)) {
        Debug.print("Issue failed in processIssue with error: " # e);
        #InvalidAmount(e);
      };
      case (#ok({ totalSupply = newSupply; transferAmount })) {
        Debug.print("Process issue succeeded");
        Debug.print("New supply: " # debug_show (newSupply));
        Debug.print("Transfer amount: " # debug_show (transferAmount));

        switch (await* mintTokens({ owner = caller; subaccount = null }, transferAmount)) {
          case (#Err(#GenericError({ message }))) {
            Debug.print("Minting failed with generic error: " # message);
            #InvalidAmount(message);
          };
          case (#Err(_)) {
            Debug.print("Minting failed with unexpected error");
            #InvalidAmount("Unexpected error during minting");
          };
          case (#Ok(_)) {
            Debug.print("Minting succeeded");
            totalSupply := newSupply;
            Debug.print("=== Issue Operation Completed Successfully ===");
            #Success;
          };
        };
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
    totalSupply;
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
      case (#err(#trappable(err))) #Err(#InsufficientFunds({ balance = 0 })); // Match the expected error format
      case (#err(#awaited(err))) #Err(#InsufficientFunds({ balance = 0 })); // Match the expected error format
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

    if (amount % supplyUnit != 0) {
      return #Err(#GenericError({ message = "Amount must be multiple of supply unit"; error_code = 3 }));
    };

    switch (
      await* getIcrc1().mint_tokens(
        Principal.fromActor(this),
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

  // -- Query Methods --

  /// Returns whether token is initialized
  public query func isInitialized() : async Bool {
    hasInitialized;
  };

  /// Returns list of backing tokens
  public query func getBackingTokens() : async [Backing.BackingPair] {
    Array.freeze(backingTokens);
  };

  /// Returns the total supply
  public query func getTotalSupply() : async Nat {
    totalSupply;
  };

  // -- Admin Functions --

  /// Update owner to new principal
  public shared ({ caller }) func updateOwner(newOwner : Principal) : async Bool {
    if (caller != owner) Debug.trap("Unauthorized");
    owner := newOwner;
    true;
  };
};
