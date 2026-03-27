class FeatureFlags {
  const FeatureFlags._();

  /// Toggle lightweight debug-only query telemetry.
  static const bool enablePerfTelemetry = bool.fromEnvironment(
    'ENABLE_PERF_TELEMETRY',
    defaultValue: true,
  );

  /// Rollout toggle for incremental order-history pagination.
  static const bool enableOrdersPaging = bool.fromEnvironment(
    'ENABLE_ORDERS_PAGING',
    defaultValue: true,
  );

  /// Hard caps to prevent accidental high-cost reads.
  static const int maxProductPageSize = int.fromEnvironment(
    'MAX_PRODUCT_PAGE_SIZE',
    defaultValue: 60,
  );

  static const int defaultOrdersPageSize = int.fromEnvironment(
    'DEFAULT_ORDERS_PAGE_SIZE',
    defaultValue: 20,
  );

  static const int maxOrdersPageSize = int.fromEnvironment(
    'MAX_ORDERS_PAGE_SIZE',
    defaultValue: 50,
  );

  static const int maxOrdersFetch = int.fromEnvironment(
    'MAX_ORDERS_FETCH',
    defaultValue: 200,
  );
}
