import TrieMap "mo:base/TrieMap";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Order "mo:base/Order";

actor class MultiHistory() = {

  // ============ TYPE DEFINITIONS ============

  public type Token = Principal;

  public type BackingPair = {
    token : Token;
    backingUnit : Nat;
  };

  public type BackingConfig = {
    supplyUnit : Nat;
    totalSupply : Nat;
    backingPairs : [BackingPair];
    multiToken : Token;
  };

  public type Snapshot = {
    timestamp : Time.Time;
    prices : [(Token, Nat)];
    approvedTokens : [Token];
    backing : BackingConfig;
  };

  // For paginated results
  public type SnapshotWithIndex = {
    index : Nat;
    timestamp : Time.Time;
    snapshot : Snapshot;
  };

  public type PaginatedSnapshots = {
    snapshots : [SnapshotWithIndex];
    totalCount : Nat;
    startIndex : Nat;
    endIndex : Nat;
  };

  // ============ STATE ============

  // Use stable entries for upgrade persistence
  private stable var snapshotEntries : [(Time.Time, Snapshot)] = [];

  // Keep a sorted array of timestamps for indexing
  private stable var sortedTimestamps : [Time.Time] = [];

  // TrieMap for efficient lookups - Time.Time is Int, so use Int.equal
  private var snapshots = TrieMap.fromEntries<Time.Time, Snapshot>(
    snapshotEntries.vals(),
    Int.equal,
    Int.hash,
  );

  private stable var latestTimestamp : Time.Time = 0;
  private stable var latestSnapshotCache : ?Snapshot = null;

  // ============ UPGRADE HOOKS ============

  system func preupgrade() {
    snapshotEntries := Iter.toArray(snapshots.entries());
  };

  system func postupgrade() {
    snapshotEntries := [];
    // Rebuild sorted timestamps if needed
    if (sortedTimestamps.size() == 0 and snapshotEntries.size() > 0) {
      sortedTimestamps := Array.sort(
        Array.map(snapshotEntries, func(e : (Time.Time, Snapshot)) : Time.Time = e.0),
        Int.compare,
      );
    };
  };

  // ============ HELPERS ============

  private func roundToMinute(time : Time.Time) : Time.Time {
    let minute = 60_000_000_000;
    (time / minute) * minute;
  };

  // Update sorted timestamps array
  private func updateSortedTimestamps() {
    let timestamps = Iter.toArray(
      Iter.map(snapshots.entries(), func(e : (Time.Time, Snapshot)) : Time.Time = e.0)
    );
    sortedTimestamps := Array.sort(timestamps, Int.compare);
  };

  // Internal helper to get snapshots by index range
  private func getSnapshotsByIndexRangeInternal(
    startIndex : Nat,
    endIndex : Nat,
  ) : PaginatedSnapshots {
    let totalCount = sortedTimestamps.size();

    // Handle empty case
    if (totalCount == 0) {
      return {
        snapshots = [];
        totalCount = 0;
        startIndex = 0;
        endIndex = 0;
      };
    };

    // Handle out of bounds - return empty result
    if (startIndex >= totalCount) {
      return {
        snapshots = [];
        totalCount = totalCount;
        startIndex = startIndex;
        endIndex = startIndex;
      };
    };

    // Clamp indices to valid range
    let actualStart = startIndex;
    let actualEnd = Nat.min(endIndex, totalCount - 1);

    var results : [SnapshotWithIndex] = [];

    for (i in Iter.range(actualStart, actualEnd)) {
      let timestamp = sortedTimestamps[i];
      switch (snapshots.get(timestamp)) {
        case (?snapshot) {
          results := Array.append(results, [{ index = i; timestamp = timestamp; snapshot = snapshot }]);
        };
        case null {};
      };
    };

    {
      snapshots = results;
      totalCount = totalCount;
      startIndex = actualStart;
      endIndex = actualEnd;
    };
  };

  // ============ PUBLIC INTERFACE ============

  public shared func recordSnapshot(
    prices : [(Token, Nat)],
    approvedTokens : [Token],
    backing : BackingConfig,
  ) : async () {
    let now = roundToMinute(Time.now());

    let snapshot : Snapshot = {
      timestamp = now;
      prices = prices;
      approvedTokens = approvedTokens;
      backing = backing;
    };

    snapshots.put(now, snapshot);

    latestTimestamp := now;
    latestSnapshotCache := ?snapshot;

    // Update sorted timestamps
    updateSortedTimestamps();
  };

  // BATCH FUNCTION - Record multiple snapshots at once
  public shared func recordSnapshotBatch(
    batch : [{
      timestamp : Time.Time;
      prices : [(Token, Nat)];
      approvedTokens : [Token];
      backing : BackingConfig;
    }]
  ) : async Nat {
    var count = 0;

    for (item in batch.vals()) {
      let snapshot : Snapshot = {
        timestamp = item.timestamp;
        prices = item.prices;
        approvedTokens = item.approvedTokens;
        backing = item.backing;
      };

      snapshots.put(item.timestamp, snapshot);

      // Update latest if this is newer
      if (item.timestamp > latestTimestamp) {
        latestTimestamp := item.timestamp;
        latestSnapshotCache := ?snapshot;
      };

      count += 1;
    };

    // Update sorted timestamps once after batch
    updateSortedTimestamps();

    count;
  };

  // ============ IMPROVED QUERY FUNCTIONS ============

  public query func getLatest() : async ?Snapshot {
    latestSnapshotCache;
  };

  public query func getSnapshotAt(timestamp : Time.Time) : async ?Snapshot {
    let minute = roundToMinute(timestamp);
    snapshots.get(minute);
  };

  // Get snapshot by index (0-based)
  public query func getSnapshotByIndex(index : Nat) : async ?SnapshotWithIndex {
    if (index >= sortedTimestamps.size()) {
      return null;
    };

    let timestamp = sortedTimestamps[index];
    switch (snapshots.get(timestamp)) {
      case (?snapshot) {
        ?{
          index = index;
          timestamp = timestamp;
          snapshot = snapshot;
        };
      };
      case null { null };
    };
  };

  // Get snapshots in a time range
  public query func getSnapshotsInTimeRange(
    startTime : Time.Time,
    endTime : Time.Time,
    maxResults : ?Nat,
  ) : async [SnapshotWithIndex] {
    let max = switch (maxResults) {
      case (?m) { m };
      case null { 1000 }; // Default max
    };

    var results : [SnapshotWithIndex] = [];
    var count = 0;

    let totalCount = sortedTimestamps.size();
    if (totalCount == 0) {
      return [];
    };

    for (i in Iter.range(0, totalCount - 1)) {
      if (count >= max) {
        return results;
      };

      let timestamp = sortedTimestamps[i];
      if (timestamp >= startTime and timestamp <= endTime) {
        switch (snapshots.get(timestamp)) {
          case (?snapshot) {
            results := Array.append(results, [{ index = i; timestamp = timestamp; snapshot = snapshot }]);
            count += 1;
          };
          case null {};
        };
      };
    };

    results;
  };

  // Get snapshots by index range (for pagination)
  public query func getSnapshotsByIndexRange(
    startIndex : Nat,
    endIndex : Nat,
  ) : async PaginatedSnapshots {
    getSnapshotsByIndexRangeInternal(startIndex, endIndex);
  };

  // Get paginated snapshots (page-based)
  // page: 0-based page number
  // pageSize: number of items per page
  public query func getSnapshotsPaginated(
    page : Nat,
    pageSize : Nat,
  ) : async PaginatedSnapshots {
    if (pageSize == 0) {
      return {
        snapshots = [];
        totalCount = sortedTimestamps.size();
        startIndex = 0;
        endIndex = 0;
      };
    };

    let startIndex = page * pageSize;
    let endIndex = startIndex + pageSize - 1;

    getSnapshotsByIndexRangeInternal(startIndex, endIndex);
  };

  // Get recent snapshots (last N)
  public query func getRecentSnapshots(count : Nat) : async [SnapshotWithIndex] {
    let totalCount = sortedTimestamps.size();
    if (totalCount == 0 or count == 0) {
      return [];
    };

    let startIndex = if (totalCount > count) {
      totalCount - count;
    } else { 0 };

    let result = getSnapshotsByIndexRangeInternal(startIndex, totalCount - 1);
    result.snapshots;
  };

  // ============ ORIGINAL QUERY FUNCTIONS ============

  public query func getPrice(token : Token) : async ?Nat {
    switch (latestSnapshotCache) {
      case (?snapshot) {
        for ((t, price) in snapshot.prices.vals()) {
          if (Principal.equal(t, token)) {
            return ?price;
          };
        };
        null;
      };
      case null { null };
    };
  };

  public query func getAllPrices() : async ?[(Token, Nat)] {
    switch (latestSnapshotCache) {
      case (?snapshot) { ?snapshot.prices };
      case null { null };
    };
  };

  public query func isApproved(token : Token) : async Bool {
    switch (latestSnapshotCache) {
      case (?snapshot) {
        for (approvedToken in snapshot.approvedTokens.vals()) {
          if (Principal.equal(approvedToken, token)) {
            return true;
          };
        };
        false;
      };
      case null { false };
    };
  };

  public query func getBacking() : async ?BackingConfig {
    switch (latestSnapshotCache) {
      case (?snapshot) { ?snapshot.backing };
      case null { null };
    };
  };

  // ============ INFO FUNCTIONS ============

  public query func getSnapshotCount() : async Nat {
    snapshots.size();
  };

  // Get all timestamps (useful for navigation)
  public query func getAllTimestamps() : async [Time.Time] {
    sortedTimestamps;
  };

  // Get info about available data
  public query func getInfo() : async {
    totalSnapshots : Nat;
    earliestTimestamp : ?Time.Time;
    latestTimestamp : ?Time.Time;
    latestIndex : ?Nat;
  } {
    let count = sortedTimestamps.size();
    {
      totalSnapshots = count;
      earliestTimestamp = if (count > 0) { ?sortedTimestamps[0] } else { null };
      latestTimestamp = if (count > 0) { ?sortedTimestamps[count - 1] } else {
        null;
      };
      latestIndex = if (count > 0) { ?(count - 1) } else { null };
    };
  };

  // Get total number of pages for a given page size
  public query func getTotalPages(pageSize : Nat) : async Nat {
    if (pageSize == 0) {
      return 0;
    };
    let totalCount = sortedTimestamps.size();
    (totalCount + pageSize - 1) / pageSize; // Ceiling division
  };
};
