import Types "Types";

module {
  // Represents the system's participation in the competition
  public type SystemStake = {
    govSystemStake : Types.Amount; // System stake in governance tokens
    multiSystemStake : Types.Amount; // System stake in multi tokens
    phantomPositions : [(Types.Token, Types.Amount)]; // System's hypothetical trades
  };
};
