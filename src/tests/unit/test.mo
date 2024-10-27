import M "mo:motoko-matchers/Matchers";
import T "mo:motoko-matchers/Testable";
import Suite "mo:motoko-matchers/Suite";
import Debug "mo:base/Debug";
import Text "mo:base/Text";

actor {
  let test_suite = Suite.suite(
    "My test suite",
    [
      Suite.suite(
        "Nat tests",
        [
          Suite.test("10 is 10", 10, M.equals(T.nat(10))),
          Suite.test("5 is greater than three", 5, M.greaterThan<Nat>(3)),
        ],
      )
    ],
  );

  public func run() : async Text {
    Debug.print("Starting tests...\n");
    Suite.run(test_suite);
    Debug.print("\nTests completed!");
    return "Tests completed: Test suite ran successfully";
  };
};
