import Principal "mo:base/Principal";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Result "mo:base/Result";

import Types "../types/Types";
import VirtualAccounts "../custodial/VirtualAccounts";
import VirtualAccountBridge "../custodial/VirtualAccountBridge";
import StakeSubmissionTypes "./StakeSubmissionTypes";
import CompetitionValidation "./CompetitionValidation";
import Error "../error/Error";

module {
  public class UserStaking(
    userAccounts : VirtualAccounts.VirtualAccounts,
    multiToken : Types.Token,
    governanceToken : Types.Token,
  ) {
    private let stakeAccounts = VirtualAccounts.VirtualAccounts(
      StableHashMap.init<Types.Account, StableHashMap.StableHashMap<Types.Token, Nat>>()
    );

    private var nextSubmissionId : StakeSubmissionTypes.SubmissionId = 0;
    private let submissions = Buffer.Buffer<StakeSubmissionTypes.StakeSubmission>(10);

    public func stake(
      account : Types.Account,
      amount : Types.Amount,
    ) {
      VirtualAccountBridge.transfer(
        userAccounts,
        stakeAccounts,
        account,
        amount,
      );
    };

    public func recordSubmission(
      account : Types.Account,
      proposedQuantity : Types.Amount,
      govStake : Types.Amount,
      multiStake : Types.Amount,
    ) : Result.Result<StakeSubmissionTypes.SubmissionId, Error.CompetitionError> {
      switch (
        CompetitionValidation.validateSubmissionBalances(
          account,
          proposedQuantity,
          govStake,
          multiStake,
          userAccounts,
        )
      ) {
        case (#err(error)) return #err(error);
        case (#ok()) {};
      };

      let submissionId = nextSubmissionId;
      nextSubmissionId += 1;

      stake(account, govStake);
      stake(account, multiStake);
      stake(account, proposedQuantity);

      let submission : StakeSubmissionTypes.StakeSubmission = {
        id = submissionId;
        participant = account;
        proposedQuantity = proposedQuantity;
        finalQuantity = null;
        govStake = govStake;
        multiStake = multiStake;
        timestamp = Time.now();
      };

      submissions.add(submission);
      #ok(submissionId);
    };

    public func getSubmission(id : StakeSubmissionTypes.SubmissionId) : ?StakeSubmissionTypes.StakeSubmission {
      if (id >= nextSubmissionId) {
        return null;
      };

      ?submissions.get(id);
    };

    public func getAllSubmissions() : [StakeSubmissionTypes.StakeSubmission] {
      Buffer.toArray(submissions);
    };

    public func getTotalGovernanceStake() : Nat {
      stakeAccounts.getTotalBalance(governanceToken).value;
    };

    public func getTotalMultiStake() : Nat {
      stakeAccounts.getTotalBalance(multiToken).value;
    };

    public func getStakeAccounts() : VirtualAccounts.VirtualAccounts {
      stakeAccounts;
    };
  };
};
