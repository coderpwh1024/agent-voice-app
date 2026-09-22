class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.accessToken,
    required this.userId,
  });

  factory AppConfig.defaults() => const AppConfig(
    baseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    ),
    accessToken: String.fromEnvironment('APP_ACCESS_TOKEN'),
    userId: String.fromEnvironment('APP_USER_ID'),
  );

  final String baseUrl;
  final String accessToken;
  final String userId;

  bool get isComplete =>
      Uri.tryParse(baseUrl)?.hasScheme == true && accessToken.trim().isNotEmpty;

  AppConfig copyWith({String? baseUrl, String? accessToken, String? userId}) {
    return AppConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
    );
  }
}
