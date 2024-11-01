import ICRC2 "mo:icrc2-types";
import BackingTypes "./backing_types";
import BackingValidation "./backing_validation";
import BackingMath "./backing_math";

module {
  // Re-export types
  public type Token = ICRC2.Service;
  public type BackingPair = BackingTypes.BackingPair;
  public type BackingConfig = BackingTypes.BackingConfig;

  // Re-export validation functions
  public let validateBacking = BackingValidation.validateBacking;
  public let validateBackingConfig = BackingValidation.validateBackingConfig;

  // Re-export math functions
  public let calculateEta = BackingMath.calculateEta;
  public let calculateBackingUnits = BackingMath.calculateBackingUnits;
  public let validateBackingRatios = BackingMath.validateBackingRatios;
};
