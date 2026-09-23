namespace CrestCore.Contracts;

/// A progress sample's estimator state or clock reading is not valid.
public sealed record InvalidDownloadSample() : Rejection;
