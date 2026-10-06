/// Sentinel used by model `copyWith` methods to distinguish "argument not
/// provided" from an explicit `null`.
///
/// Nullable model fields need this: `copyWith()` with a plain nullable
/// parameter cannot tell `copyWith(description: null)` (clear the field) apart
/// from `copyWith()` (leave it alone).
const Object unset = Object();
