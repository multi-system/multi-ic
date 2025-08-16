import Types "Types";

module {
  // Represents the system's participation in the competition
  public type SystemStake = {
    systemStakes : [(Types.Token, Types.Amount)]; // System stakes per token type
    phantomPositions : [(Types.Token, Types.Amount)]; // System's hypothetical trades
  };
};
