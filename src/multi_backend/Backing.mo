import ICRC2 "mo:icrc2-types";
import BackingTypes "./BackingTypes";
import BackingValidation "./BackingValidation";
import BackingMath "./BackingMath";
import BackingOperations "./BackingOperations";

module {
  public type Token = ICRC2.Service;
  public type BackingPair = BackingTypes.BackingPair;
  public type BackingConfig = BackingTypes.BackingConfig;

  // Validation
  public let validateBackingFull = BackingValidation.validateBackingFull;

  // Math operations
  public let calculateRequiredBacking = BackingMath.calculateRequiredBacking;

  // Token operations
  public let processIssue = BackingOperations.processIssue;
};
