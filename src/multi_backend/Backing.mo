import ICRC2 "mo:icrc2-types";
import BackingTypes "./BackingTypes";
import BackingValidation "./BackingValidation";
import BackingMath "./BackingMath";

module {
  public type Token = ICRC2.Service;
  public type BackingPair = BackingTypes.BackingPair;
  public type BackingConfig = BackingTypes.BackingConfig;
  public let validateBackingFull = BackingValidation.validateBackingFull;
};
