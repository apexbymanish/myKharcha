import AppIntents

/// Marks this module as an App Intents package so the system can discover
/// LogExpenseIntent, LogIncomeIntent, LogDebtIntent, etc. without any of them
/// needing to be listed by hand. `includedPackages` defaults to `[]` in the
/// protocol extension, which is correct here — KharchaKit has no sub-packages.
public struct KharchaKitPackage: AppIntentsPackage {}
