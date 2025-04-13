import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Types "Types";
import RewardTypes "RewardTypes";

module {
  // Execution price information for a token
  public type ExecutionPriceInfo = {
    token : Types.Token;
    executionPrice : Types.Price; // Final price used for settlement
  };

  // Record of a settlement operation
  public type SettlementRecord = {
    tokenAmounts : [(Types.Token, Types.Amount)]; // Tokens acquired
    multiMinted : Types.Amount; // Total Multi tokens minted for acquisitions
    systemStakeMinted : Types.Amount; // Multi tokens minted for system stake
    timestamp : Time.Time; // When settlement occurred
  };
};
