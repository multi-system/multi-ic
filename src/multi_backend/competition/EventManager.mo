import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import StableHashMap "mo:stablehashmap/FunctionalStableHashMap";

import Types "../types/Types";
import EventTypes "../types/EventTypes";
import CompetitionEntryTypes "../types/CompetitionEntryTypes";
import CompetitionRegistryTypes "../types/CompetitionRegistryTypes";

/**
 * EventManager provides a unified interface for managing heartbeats and price events.
 * It wraps the event registry functionality with convenient methods for the orchestrator.
 */
module {
  public class EventManager(
    eventRegistry : CompetitionRegistryTypes.EventRegistry
  ) {
    /**
     * Record a new heartbeat event
     *
     * @param currentTime Current timestamp
     * @return ID of the new heartbeat event
     */
    public func recordHeartbeat(currentTime : Time.Time) : Nat {
      let heartbeatId = eventRegistry.nextHeartbeatId;

      // Create new heartbeat event
      let heartbeatEvent : EventTypes.HeartbeatEvent = {
        id = heartbeatId;
        timestamp = currentTime;
      };

      // Store in the registry
      StableHashMap.put(
        eventRegistry.heartbeats,
        Nat.equal,
        Hash.hash,
        heartbeatId,
        heartbeatEvent,
      );

      // Update counters
      eventRegistry.nextHeartbeatId += 1;
      eventRegistry.lastUpdateTime := currentTime;

      Debug.print("EventManager: Recorded heartbeat #" # Nat.toText(heartbeatId));
      heartbeatId;
    };

    /**
     * Record current prices as a new price event.
     * In production, this would fetch real market prices.
     *
     * @return ID of the new price event
     */
    public func recordCurrentPrices() : Nat {
      // Get the latest heartbeat ID
      let heartbeatId = if (eventRegistry.nextHeartbeatId > 0) {
        eventRegistry.nextHeartbeatId - 1;
      } else {
        Debug.trap("No heartbeat recorded yet");
      };

      let priceEventId = eventRegistry.nextPriceEventId;

      // Create dummy prices for now
      // In production, this would fetch real prices from oracles
      let prices : [Types.Price] = [];

      // Create price event
      let priceEvent : EventTypes.PriceEvent = {
        id = priceEventId;
        heartbeatId = heartbeatId;
        prices = prices;
      };

      // Store in the registry
      StableHashMap.put(
        eventRegistry.priceEvents,
        Nat.equal,
        Hash.hash,
        priceEventId,
        priceEvent,
      );

      // Update counter
      eventRegistry.nextPriceEventId += 1;

      Debug.print("EventManager: Recorded price event #" # Nat.toText(priceEventId));
      priceEventId;
    };

    /**
     * Create a distribution event for a competition
     *
     * @param priceEventId The price event ID to use
     * @param distributionNumber The distribution number (0-based)
     * @return The distribution event
     */
    public func createDistributionEvent(
      priceEventId : Nat,
      distributionNumber : Nat,
    ) : CompetitionEntryTypes.DistributionEvent {
      {
        distributionPrices = priceEventId;
        distributionNumber = distributionNumber;
      };
    };

    /**
     * Get a heartbeat event by ID
     */
    public func getHeartbeatEvent(id : Nat) : ?EventTypes.HeartbeatEvent {
      StableHashMap.get(
        eventRegistry.heartbeats,
        Nat.equal,
        Hash.hash,
        id,
      );
    };

    /**
     * Get a price event by ID
     */
    public func getPriceEvent(id : Nat) : ?EventTypes.PriceEvent {
      StableHashMap.get(
        eventRegistry.priceEvents,
        Nat.equal,
        Hash.hash,
        id,
      );
    };

    /**
     * Get the latest price event
     */
    public func getLatestPriceEvent() : ?EventTypes.PriceEvent {
      if (eventRegistry.nextPriceEventId == 0) {
        return null;
      };

      getPriceEvent(eventRegistry.nextPriceEventId - 1);
    };

    /**
     * Check if we already have a price event for a given heartbeat
     */
    public func hasPriceEventForHeartbeat(heartbeatId : Nat) : ?Nat {
      // Check all price events to see if one exists for this heartbeat
      for ((id, event) in StableHashMap.entries(eventRegistry.priceEvents)) {
        if (event.heartbeatId == heartbeatId) {
          return ?id;
        };
      };
      null;
    };
  };
};
