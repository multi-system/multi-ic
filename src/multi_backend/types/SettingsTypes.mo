import Types "Types";

module {
  public type SettingsState = {
    var approvedTokens : [Types.Token];
    var governanceToken : ?Types.Token;
  };
};
