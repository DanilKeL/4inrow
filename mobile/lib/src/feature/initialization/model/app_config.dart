final class AppConfig {
  const new({required this.apiBaseUrl, required this.onlineUrl});

  factory fromEnvironment() {
    const api = String.fromEnvironment(
      'FOUR_API_BASE_URL',
      defaultValue: 'https://4inrow.ru',
    );
    const configuredOnline = String.fromEnvironment('FOUR_ONLINE_URL');
    final Uri base = Uri.parse(api);
    final online = configuredOnline.isNotEmpty
        ? configuredOnline
        : base
              .replace(
                scheme: base.scheme == 'https' ? 'wss' : 'ws',
                path: '/online',
              )
              .toString();
    return AppConfig(apiBaseUrl: api, onlineUrl: online);
  }

  final String apiBaseUrl;
  final String onlineUrl;
}
