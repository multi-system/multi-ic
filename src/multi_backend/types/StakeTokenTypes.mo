import Types "Types";

module {
  // Configuration for a single accepted stake token, defined in the competition config.
  public type StakeTokenConfig = {
    token : Types.Token;
    baseRate : Types.Ratio;
    systemMultiplier : Types.Ratio;
  };
};
