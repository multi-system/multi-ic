import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Principal "mo:base/Principal";

import Types "../types/Types";

module {
  // Generic helper to find value in token-keyed array
  public func findInTokenArray<T>(
    arr : [(Types.Token, T)],
    token : Types.Token,
  ) : ?T {
    Array.find<(Types.Token, T)>(
      arr,
      func((t, _)) = Principal.equal(t, token),
    ) |> Option.map<(Types.Token, T), T>(_, func((_, v)) = v);
  };

  // Generic helper to update value in token-keyed array
  public func updateInTokenArray<T>(
    arr : [(Types.Token, T)],
    token : Types.Token,
    value : T,
  ) : [(Types.Token, T)] {
    let buffer = Buffer.Buffer<(Types.Token, T)>(arr.size() + 1);
    var found = false;

    for ((t, v) in arr.vals()) {
      if (Principal.equal(t, token)) {
        buffer.add((t, value));
        found := true;
      } else {
        buffer.add((t, v));
      };
    };

    if (not found) {
      buffer.add((token, value));
    };

    Buffer.toArray(buffer);
  };

  // Helper to get value with default if not found
  public func getWithDefault<T>(
    arr : [(Types.Token, T)],
    token : Types.Token,
    default : T,
  ) : T {
    Option.get(findInTokenArray(arr, token), default);
  };

  // Helper to remove item from token-keyed array
  public func removeFromTokenArray<T>(
    arr : [(Types.Token, T)],
    token : Types.Token,
  ) : [(Types.Token, T)] {
    Array.filter<(Types.Token, T)>(
      arr,
      func((t, _)) = not Principal.equal(t, token),
    );
  };

  // Helper to check if token exists in array
  public func tokenExists<T>(
    arr : [(Types.Token, T)],
    token : Types.Token,
  ) : Bool {
    Option.isSome(findInTokenArray(arr, token));
  };
};
