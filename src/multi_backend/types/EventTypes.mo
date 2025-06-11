import Time "mo:base/Time";
import Types "Types";

module {
  // Heartbeat event - records every system tick
  public type HeartbeatEvent = {
    id : Nat; // Incremental heartbeat ID
    timestamp : Time.Time; // When heartbeat occurred
  };

  // Price event - only created when needed
  public type PriceEvent = {
    id : Nat; // Incremental price event ID
    heartbeatId : Nat; // Reference to which heartbeat this belongs to
    prices : [Types.Price]; // The actual price data
  };
};
