class FeatureFlags {
  const FeatureFlags._();

  /// Toggle lightweight debug-only query telemetry.
  static const bool enablePerfTelemetry = bool.fromEnvironment(
    'ENABLE_PERF_TELEMETRY',
    defaultValue: true,
  );

  /// Toggle debug-only image bandwidth telemetry (cache hit/miss + bytes).
  static const bool enableImageBandwidthTelemetry = bool.fromEnvironment(
    'ENABLE_IMAGE_BANDWIDTH_TELEMETRY',
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

  /// Splash hardening flags (phase 1)
  static const bool enableSplashWatchdog = bool.fromEnvironment(
    'ENABLE_SPLASH_WATCHDOG',
    defaultValue: true,
  );

  static const int splashMinDurationMs = int.fromEnvironment(
    'SPLASH_MIN_DURATION_MS',
    defaultValue: 1700,
  );

  static const int splashWatchdogTimeoutMs = int.fromEnvironment(
    'SPLASH_WATCHDOG_TIMEOUT_MS',
    defaultValue: 7000,
  );

  static const int splashUserDocTimeoutMs = int.fromEnvironment(
    'SPLASH_USER_DOC_TIMEOUT_MS',
    defaultValue: 3500,
  );

  /// Home startup loading optimizations (phase 2)
  static const bool enableHomeStartupLite = bool.fromEnvironment(
    'ENABLE_HOME_STARTUP_LITE',
    defaultValue: true,
  );

  static const int homeStartupProductPool = int.fromEnvironment(
    'HOME_STARTUP_PRODUCT_POOL',
    defaultValue: 24,
  );

  static const bool enableDeferredHomeTaxonomy = bool.fromEnvironment(
    'ENABLE_DEFERRED_HOME_TAXONOMY',
    defaultValue: true,
  );

  static const bool enableHomeStartupCache = bool.fromEnvironment(
    'ENABLE_HOME_STARTUP_CACHE',
    defaultValue: true,
  );

  static const int homeProductsPageTimeoutMs = int.fromEnvironment(
    'HOME_PRODUCTS_PAGE_TIMEOUT_MS',
    defaultValue: 5500,
  );

  static const int homeBannersTimeoutMs = int.fromEnvironment(
    'HOME_BANNERS_TIMEOUT_MS',
    defaultValue: 4500,
  );

  static const int homeTaxonomyTimeoutMs = int.fromEnvironment(
    'HOME_TAXONOMY_TIMEOUT_MS',
    defaultValue: 5000,
  );
}
