import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

import Types "../../types/Types";
import RewardTypes "../../types/RewardTypes";
import SystemStakeTypes "../../types/SystemStakeTypes";

/**
 * Handles the creation of phantom position records for system participation.
 * No actual token transfers occur with phantom positions.
 */
module {
  public class PhantomPositionSettlement() {
    /**
     * Creates a phantom position record for system participation.
     * No actual token transfers occur, this just creates a record.
     *
     * @param token The token being represented
     * @param amount The amount of the token
     * @param systemStake The system stake information
     * @returns A RewardTypes.Position recording the phantom position
     */
    public func createPhantomPosition(
      token : Types.Token,
      amount : Types.Amount,
      systemStake : SystemStakeTypes.SystemStake,
    ) : RewardTypes.Position {
      // Verify token matches
      if (not Principal.equal(token, amount.token)) {
        Debug.trap("Critical error: Token mismatch in createPhantomPosition");
      };

      // Create and return a Position for reward tracking
      {
        quantity = amount;
        govStake = systemStake.govSystemStake;
        multiStake = systemStake.multiSystemStake;
        submissionId = null; // System positions don't have a submission ID
        isSystem = true;
      };
    };
  };
};
