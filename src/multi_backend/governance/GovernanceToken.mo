import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Result "mo:base/Result";
import Error "mo:base/Error";

shared ({ caller = deployer }) actor class GovernanceToken(
    args : ?{
        icrc1 : ?ICRC1.InitArgs;
        icrc2 : ?ICRC2.InitArgs;
    }
) = this {
    // -- State Variables --
    private let owner : Principal = deployer;

    // -- ICRC1 Setup --
    let defaultIcrc1Args : ICRC1.InitArgs = {
        name = ?"Multi Governance";
        symbol = ?"GOV";
        logo = ?"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==";
        decimals = 8;
        fee = ?#Fixed(10000);
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
        max_allowance = ?#TotalSupply;
        fee = ?#ICRC1;
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

    // -- Minting Function --
    public shared ({ caller }) func mint(args : { to : ICRC1.Account; amount : Nat }) : async ICRC1.TransferResult {
        if (caller != owner) {
            return #Err(#GenericError({ message = "Only owner can mint"; error_code = 1 }));
        };

        switch (
            await* getIcrc1().mint_tokens(
                caller,
                {
                    to = args.to;
                    amount = args.amount;
                    memo = null;
                    created_at_time = null;
                },
            )
        ) {
            case (#trappable(val)) val;
            case (#awaited(val)) val;
            case (#err(#trappable(err))) #Err(#GenericError({ message = err; error_code = 2 }));
            case (#err(#awaited(err))) #Err(#GenericError({ message = err; error_code = 2 }));
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
};
