import ICRC2 "mo:icrc2-types";
import BackingTypes "./BackingTypes";
import BackingValidation "./BackingValidation";
import BackingMath "./BackingMath";

module {
  /// Re-exported types
  public type Token = ICRC2.Service;
  public type BackingPair = BackingTypes.BackingPair;
  public type BackingConfig = BackingTypes.BackingConfig;

  /// Re-exported validation functions
  public let validateBacking = BackingValidation.validateBacking;
  public let validateBackingConfig = BackingValidation.validateBackingConfig;

  /// Re-exported math functions
  public let calculateEta = BackingMath.calculateEta;
  public let calculateBackingUnits = BackingMath.calculateBackingUnits;
  public let validateBackingRatios = BackingMath.validateBackingRatios;
  public let calculateRequiredBacking = BackingMath.calculateRequiredBacking;
};
