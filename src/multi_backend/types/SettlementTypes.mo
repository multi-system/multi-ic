import Time "mo:base/Time";
import Types "Types";
import RewardTypes "RewardTypes";
import SystemStakeTypes "SystemStakeTypes";

module {
  // Current status of the settlement process
  public type SettlementStatus = {
    #NotStarted; // Settlement hasn't begun
    #PriceDiscovery; // Market price discovery phase
    #Settling; // Active settlement of assets
    #Completed; // Settlement completed
  };

  // Tracks price information for a token during settlement
  public type PriceDiscovery = {
    token : Types.Token;
    competitionPrice : Types.Price; // Original price from competition
    marketPrice : ?Types.Price; // Best price offered by market
    executionPrice : Types.Price; // Final price used for settlement
  };

  // Current state of the settlement process
  public type SettlementState = {
    status : SettlementStatus;
    priceDiscoveries : [PriceDiscovery];
    totalSegments : Nat; // Total segments for gradual settlement
    completedSegments : Nat; // Number of segments processed
    lastSettlementTime : ?Time.Time; // When last segment was processed
    positions : [RewardTypes.Position]; // All positions being settled
    systemStake : SystemStakeTypes.SystemStake; // System participation
  };

  // Records a segment of the gradual settlement process
  public type SettlementSegment = {
    segmentId : Nat;
    tokenAmounts : [(Types.Token, Types.Amount)]; // Tokens acquired
    multiMinted : Types.Amount; // Tokens minted to pay users
    systemStakeMinted : Types.Amount; // Tokens minted for system stake
    timestamp : Time.Time;
  };
};
