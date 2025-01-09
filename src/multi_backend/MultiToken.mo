import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Types "./types/BackingTypes";
import _ "./types/VirtualTypes";
import BackingOperations "./backing/BackingOperations";
import LedgerManager "./ledger/LedgerManager";
import BackingMath "./backing/BackingMath";
import BackingValidation "./backing/BackingValidation";
import Messages "./types/Messages";
import VirtualAccounts "./ledger/VirtualAccounts";

shared ({ caller = deployer }) actor class MultiToken(
  args : ?{
    icrc1 : ?ICRC1.InitArgs;
    icrc2 : ?ICRC2.InitArgs;
  }
) = this {
  // -- State Variables --
  private var hasInitialized : Bool = false;
  private var backingTokens : [var Types.BackingPair] = [var];
  private var supplyUnit : Nat = 0;
  private var totalSupply : Nat = 0;
  private let owner : Principal = deployer;

  // -- Virtual Accounts Setup --
  private let virtualAccounts = VirtualAccounts.VirtualAccountManager();

  // -- Middleware Setup --
  private var ledgerManager_ : ?LedgerManager.LedgerManager = null;
  private let backingImpl = BackingOperations.BackingOperationsImpl(virtualAccounts);

  private func getLedgerManager() : LedgerManager.LedgerManager {
    switch (ledgerManager_) {
      case (null) {
        let instance = LedgerManager.LedgerManager(
          Principal.fromActor(this),
          virtualAccounts,
        );
        ledgerManager_ := ?instance;
        instance;
      };
      case (?val) val;
    };
  };

  // -- ICRC1 Setup --
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
    min_burn_amount = null;
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

  let #v0_1_0(#data(_)) = icrc1State;
  let #v0_1_0(#data(_)) = icrc2State;

  private var icrc1Instance_ : ?ICRC1.ICRC1 = null;
  private var icrc2Instance_ : ?ICRC2.ICRC2 = null;

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

  private func getIcrc2Environment() : ICRC2.Environment {
    {
      icrc1 = getIcrc1();
      get_fee = null;
      can_approve = null;
      can_transfer_from = null;
    };
  };

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

  public shared ({ caller = _ }) func initialize(msg : Messages.InitializeMsg) : async Result.Result<(), Text> {
    if (hasInitialized) return #err("Already initialized");

    let internalConfig : Types.BackingConfig = {
      supplyUnit = msg.supplyUnit;
      totalSupply = 0;
      backingPairs = Array.map<Messages.TokenConfig, Types.BackingPair>(
        msg.backingTokens,
        func(tc : Messages.TokenConfig) : Types.BackingPair {
          {
            tokenInfo = {
              canisterId = tc.canisterId;
            };
            backingUnit = tc.backingUnit;
            reserveQuantity = 0;
          };
        },
      );
    };

    switch (BackingValidation.validateConfig(internalConfig)) {
      case (#err(e)) return #err(e);
      case (#ok()) {
        // Initialize ledger manager
        getLedgerManager().initializeLedgers<system>(
          Array.map(
            internalConfig.backingPairs,
            func(p : Types.BackingPair) : Principal = p.tokenInfo.canisterId,
          )
        );

        backingTokens := Array.thaw(internalConfig.backingPairs);
        supplyUnit := internalConfig.supplyUnit;
        hasInitialized := true;

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

  public shared ({ caller }) func deposit(args : Messages.DepositArgs) : async Messages.OperationResponse {
    if (not hasInitialized) {
      return #NotInitialized;
    };

    // Verify token is one of our backing tokens
    let ?backingToken = Array.find<Types.BackingPair>(
      Array.freeze(backingTokens),
      func(p) = p.tokenInfo.canisterId == args.token,
    ) else return #TransferFailed({
      token = args.token;
      error = "Token not supported";
    });

    switch (await* getLedgerManager().deposit(caller, args.token, args.amount)) {
      case (#err(e)) { #TransferFailed({ token = args.token; error = e }) };
      case (#ok()) { #Success };
    };
  };

  public shared ({ caller }) func withdraw(args : Messages.WithdrawArgs) : async Messages.OperationResponse {
    if (not hasInitialized) {
      return #NotInitialized;
    };

    switch (await* getLedgerManager().withdraw(caller, args.token, args.amount)) {
      case (#err(e)) { #TransferFailed({ token = args.token; error = e }) };
      case (#ok()) { #Success };
    };
  };

  public shared ({ caller }) func issue(args : Messages.IssueArgs) : async Messages.IssueResponse {
    if (not hasInitialized) {
      return #NotInitialized;
    };
    let backingPairsArray = Array.freeze(backingTokens);
    switch (
      backingImpl.processIssue(
        caller,
        Principal.fromActor(this),
        args.amount,
        supplyUnit,
        totalSupply,
        backingPairsArray,
      )
    ) {
      case (#err(e)) {
        #InvalidAmount(e);
      };
      case (#ok({ totalSupply = newSupply; amount })) {
        switch (await* mintTokens({ owner = caller; subaccount = null }, amount)) {
          case (#Ok(_)) {
            totalSupply := newSupply;
            #Success;
          };
          case (#Err(_)) {
            Debug.trap("Critical error: Backing tokens transferred but mint failed");
          };
        };
      };
    };
  };

  public shared ({ caller }) func redeem(args : Messages.RedeemArgs) : async Messages.RedeemResponse {
    if (not hasInitialized) {
      return #NotInitialized;
    };

    // Check balance first
    let balance = getIcrc1().balance_of({ owner = caller; subaccount = null });
    if (balance < args.amount) {
      return #InvalidAmount("Insufficient balance");
    };

    let backingPairsArray = Array.freeze(backingTokens);
    switch (
      backingImpl.processRedeem(
        caller,
        Principal.fromActor(this),
        args.amount,
        supplyUnit,
        totalSupply,
        backingPairsArray,
      )
    ) {
      case (#err(e)) {
        #InvalidAmount(e);
      };
      case (#ok({ totalSupply = newSupply; amount })) {
        switch (await* burnTokens({ owner = caller; subaccount = null }, amount)) {
          case (#Ok(_)) {
            totalSupply := newSupply;
            #Success;
          };
          case (#Err(_)) {
            Debug.trap("Critical error: Backing tokens transferred but burn failed");
          };
        };
      };
    };
  };

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

  private func burnTokens(from : ICRC1.Account, amount : Nat) : async* ICRC1.TransferResult {
    if (not hasInitialized) {
      return #Err(#GenericError({ message = "Not initialized"; error_code = 1 }));
    };
    if (amount % supplyUnit != 0) {
      return #Err(#GenericError({ message = "Amount must be multiple of supply unit"; error_code = 3 }));
    };

    switch (
      await* getIcrc1().burn_tokens(
        from.owner,
        {
          from_subaccount = from.subaccount;
          amount = amount;
          memo = null;
          created_at_time = null;
        },
        false,
      )
    ) {
      case (#trappable(val)) val;
      case (#awaited(val)) val;
      case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 5 }));
      case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 5 }));
    };
  };

  // -- Query Functions --
  public query func getVirtualBalance(user : Principal, token : Principal) : async Nat {
    virtualAccounts.getBalance(user, token);
  };

  public query func isInitialized() : async Bool {
    hasInitialized;
  };

  public query func getBackingTokens() : async [Types.BackingPair] {
    // Map over backing tokens and fill in reserve quantities from virtual balances
    Array.map<Types.BackingPair, Types.BackingPair>(
      Array.freeze(backingTokens),
      func(pair : Types.BackingPair) : Types.BackingPair {
        {
          tokenInfo = pair.tokenInfo;
          backingUnit = pair.backingUnit;
          reserveQuantity = virtualAccounts.getBalance(Principal.fromActor(this), pair.tokenInfo.canisterId);
        };
      },
    );
  };

  public query func getTotalSupply() : async Nat {
    totalSupply;
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
};
