import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import ICRC2 "mo:icrc2-types";
import Types "./BackingTypes";
import BackingMath "./BackingMath";
import Debug "mo:base/Debug";
import Error "mo:base/Error";

module {
  type BackingPair = Types.BackingPair;
  type BackingConfig = Types.BackingConfig;

  public type IssueResult = {
    totalSupply : Nat;
    transferAmount : Nat;
  };

  /// Process backing token transfers and update reserves and supply
  public func processIssue(
    amount : Nat,
    supplyUnit : Nat,
    totalSupply : Nat,
    caller : Principal,
    canisterId : Principal,
    backingTokens : [var BackingPair],
  ) : async* Result.Result<IssueResult, Text> {
    Debug.print("ProcessIssue - Starting with amount: " # debug_show (amount));
    // Validate amount
    if (amount % supplyUnit != 0) {
      return #err("Amount must be multiple of supply unit");
    };

    // Calculate all required amounts up front
    let transferAmounts = Buffer.Buffer<(Nat, Nat)>(backingTokens.size());
    var i = 0;
    while (i < backingTokens.size()) {
      let pair = backingTokens[i];
      switch (BackingMath.calculateRequiredBacking(amount, supplyUnit, pair)) {
        case (#err(e)) return #err(e);
        case (#ok(requiredAmount)) {
          Debug.print("Token " # debug_show (Principal.fromActor(pair.tokenInfo.token)) # " requires " # debug_show (requiredAmount));
          transferAmounts.add((i, requiredAmount));
        };
      };
      i += 1;
    };

    // Verify allowances using pre-calculated amounts
    for ((index, requiredAmount) in transferAmounts.vals()) {
      let pair = backingTokens[index];
      switch (await verifyAllowance(caller, canisterId, pair.tokenInfo.token, requiredAmount)) {
        case (#err(e)) return #err(e);
        case (#ok()) {};
      };
    };

    // Execute transfers using the same pre-calculated amounts
    Debug.print("All allowances verified, executing transfers");
    for ((index, requiredAmount) in transferAmounts.vals()) {
      let pair = backingTokens[index];
      switch (await transferBackingTokens(caller, canisterId, pair.tokenInfo.token, requiredAmount)) {
        case (#err(e)) return #err("Transfer failed for token " # Principal.toText(Principal.fromActor(pair.tokenInfo.token)) # ": " # e);
        case (#ok()) {};
      };
    };

    // Update reserves atomically
    updateReserves(backingTokens, transferAmounts);

    Debug.print("All transfers complete, new total supply: " # debug_show (totalSupply + amount));
    #ok({
      totalSupply = totalSupply + amount;
      transferAmount = amount;
    });
  };

  private func verifyAllowance(
    caller : Principal,
    canisterId : Principal,
    token : ICRC2.Service,
    requiredAmount : Nat,
  ) : async Result.Result<(), Text> {
    Debug.print("Verifying allowance...");
    Debug.print("Required amount: " # debug_show (requiredAmount));
    let fee = await token.icrc1_fee();
    Debug.print("Token fee: " # debug_show (fee));
    let totalRequired = requiredAmount + fee;
    Debug.print("Total required (including fee): " # debug_show (totalRequired));

    let allowance = await token.icrc2_allowance({
      account = {
        owner = caller;
        subaccount = null;
      };
      spender = {
        owner = canisterId;
        subaccount = null;
      };
    });

    Debug.print("Found allowance: " # debug_show (allowance));

    if (allowance.allowance < totalRequired) {
      #err("Insufficient allowance for token: " # Principal.toText(Principal.fromActor(token)));
    } else {
      #ok();
    };
  };

  private func updateReserves(
    backingTokens : [var BackingPair],
    transfers : Buffer.Buffer<(Nat, Nat)>,
  ) {
    for ((index, amount) in transfers.vals()) {
      let pair = backingTokens[index];
      backingTokens[index] := {
        tokenInfo = pair.tokenInfo;
        backingUnit = pair.backingUnit;
        reserveQuantity = pair.reserveQuantity + amount;
      };
    };
  };

  private func transferBackingTokens(
    from : Principal,
    to : Principal,
    token : ICRC2.Service,
    amount : Nat,
  ) : async Result.Result<(), Text> {
    Debug.print("=== Transfer Details ===");
    Debug.print("From: " # Principal.toText(from));
    Debug.print("To: " # Principal.toText(to));
    Debug.print("Amount: " # debug_show (amount));
    Debug.print("Token: " # Principal.toText(Principal.fromActor(token)));

    try {
      let fee = await token.icrc1_fee();
      Debug.print("Token fee: " # debug_show (fee));

      let args = {
        from = { owner = from; subaccount = null };
        to = { owner = to; subaccount = null };
        amount = amount;
        fee = ?fee; // Include the fee
        memo = null;
        created_at_time = null;
        spender_subaccount = null;
      };
      Debug.print("Transfer args: " # debug_show (args));

      let result = await token.icrc2_transfer_from(args);
      Debug.print("Transfer result: " # debug_show (result));

      switch (result) {
        case (#Err(e)) {
          Debug.print("Transfer error: " # debug_show (e));
          #err(debug_show (e));
        };
        case (#Ok(_)) {
          Debug.print("Transfer successful");
          #ok();
        };
      };
    } catch (e) {
      Debug.print("Unexpected error: " # Error.message(e));
      #err("Unexpected error during transfer: " # Error.message(e));
    };
  };
  // Helper function to calculate total required backing for all tokens
  public func calculateTotalRequiredBacking(
    amount : Nat,
    supplyUnit : Nat,
    backingTokens : [BackingPair],
  ) : Result.Result<[(Principal, Nat)], Text> {
    let required = Buffer.Buffer<(Principal, Nat)>(backingTokens.size());

    for (pair in backingTokens.vals()) {
      switch (BackingMath.calculateRequiredBacking(amount, supplyUnit, pair)) {
        case (#err(e)) return #err(e);
        case (#ok(requiredAmount)) {
          required.add((Principal.fromActor(pair.tokenInfo.token), requiredAmount));
        };
      };
    };

    #ok(Buffer.toArray(required));
  };
};
