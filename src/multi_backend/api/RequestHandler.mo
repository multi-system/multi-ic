import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "../types/Types";
import BackingTypes "../types/BackingTypes";
import Error "../error/Error";
import BackingValidation "../backing/BackingValidation";
import Messages "./Messages";

module {
  public class RequestHandler(
    backingStore : {
      hasInitialized : () -> Bool;
      getConfig : () -> BackingTypes.BackingConfig;
      addBackingToken : (Types.Token) -> ();
      getBackingTokens : () -> [BackingTypes.BackingPair];
      initialize : (Nat, Types.Token, Types.Token) -> ();
      updateBackingTokens : ([BackingTypes.BackingPair]) -> ();
    },
    tokenRegistry : {
      approve : (Types.Token) -> Result.Result<(), Error.ApprovalError>;
      isApproved : (Types.Token) -> Bool;
      getApproved : () -> [Types.Token];
      size : () -> Nat;
    },
  ) {
    // ADMINISTRATIVE OPERATIONS

    public func approveToken(
      caller : Types.Account,
      owner : Types.Account,
      tokenRequest : Messages.TokenRequest,
      addLedger : (Types.Token) -> async* Result.Result<(), Error.ApprovalError>,
    ) : async* Result.Result<(), Error.ApprovalError> {
      let token : Types.Token = tokenRequest.canisterId;

      if (caller != owner) {
        return #err(#Unauthorized);
      };

      if (backingStore.hasInitialized()) {
        return #err(#AlreadyInitialized);
      };

      switch (BackingValidation.validateTokenApproval(token, backingStore)) {
        case (#err(e)) return #err(e);
        case (#ok()) {
          if (tokenRegistry.isApproved(token)) {
            return #err(#TokenAlreadyApproved(token));
          };

          switch (tokenRegistry.approve(token)) {
            case (#err(e)) {
              return #err(e);
            };
            case (#ok()) {
              let ledgerResult = await* addLedger(token);

              switch (ledgerResult) {
                case (#err(e)) return #err(e);
                case (#ok()) {
                  backingStore.addBackingToken(token);
                  return #ok(());
                };
              };
            };
          };
        };
      };
    };

    public func initialize(
      caller : Types.Account,
      owner : Types.Account,
      request : Messages.InitializeRequest,
      processInitialize : (
        [BackingTypes.BackingPair],
        Nat,
        Types.Token,
        Types.Token,
      ) -> Result.Result<(), Error.InitError>,
    ) : Result.Result<(), Error.InitError> {
      if (caller != owner) {
        return #err(#Unauthorized);
      };

      let multiToken : Types.Token = request.multiToken.canisterId;
      let governanceToken : Types.Token = request.governanceToken.canisterId;

      let backingPairs = Array.map<{ canisterId : Principal; backingUnit : Nat }, BackingTypes.BackingPair>(
        request.backingTokens,
        func(tokenInfo) : BackingTypes.BackingPair {
          {
            token = tokenInfo.canisterId;
            backingUnit = tokenInfo.backingUnit;
          };
        },
      );

      return processInitialize(backingPairs, request.supplyUnit, multiToken, governanceToken);
    };

    // USER OPERATIONS HELPERS

    public func validateDepositPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateWithdrawPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateIssuePreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };

    public func validateRedeemPreconditions(_ : Types.Account) : ?Messages.CommonError {
      if (not backingStore.hasInitialized()) {
        return ? #NotInitialized;
      };
      return null;
    };
  };
};
