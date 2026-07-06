import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/openrouter_service.dart';
import '../utils/in_app_browser.dart';
import '../utils/privacy_constants.dart';

enum _AuthProviderChoice { openRouter, openAICompatible }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final OpenRouterService _openRouterService = OpenRouterService();
  final TextEditingController _byoBaseUrlController = TextEditingController();
  final TextEditingController _byoTokenController = TextEditingController();
  final TextEditingController _byoHeadersController = TextEditingController();
  bool _isAuthenticating = false;
  bool _consentGiven = false;
  String? _errorMessage;
  _AuthProviderChoice _providerChoice = _AuthProviderChoice.openRouter;

  @override
  void initState() {
    super.initState();
    _loadConsentState();
    _loadProviderConfig();
  }

  @override
  void dispose() {
    _byoBaseUrlController.dispose();
    _byoTokenController.dispose();
    _byoHeadersController.dispose();
    super.dispose();
  }

  Future<void> _loadConsentState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _consentGiven = prefs.getBool('privacy_consent_given') ?? false;
      });
    }
  }

  Future<void> _saveConsentState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_consent_given', true);
  }

  Future<void> _loadProviderConfig() async {
    final isByo = await _openRouterService.isUsingOpenAICompatibleProvider();
    final byoConfig = await _openRouterService
        .getOpenAICompatibleConfigForDisplay();
    if (!mounted) return;
    setState(() {
      _providerChoice = isByo
          ? _AuthProviderChoice.openAICompatible
          : _AuthProviderChoice.openRouter;
      if (byoConfig != null) {
        _byoBaseUrlController.text = byoConfig['baseUrl'] as String? ?? '';
        _byoTokenController.text = byoConfig['bearerToken'] as String? ?? '';
        final headers = (byoConfig['headers'] as Map<String, String>?) ?? {};
        _byoHeadersController.text = headers.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('\n');
      }
    });
  }

  /// Handle OAuth callback with authorization code
  Future<void> _handleAuthCallback(Uri uri) async {
    final code = uri.queryParameters['code'];

    if (code == null) {
      setState(() {
        _errorMessage = 'No authorization code received';
        _isAuthenticating = false;
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      await _openRouterService.exchangeCodeForKey(code);
      await _saveConsentState();

      if (mounted) {
        // Navigate to conversation list
        Navigator.of(context).pushReplacementNamed('/conversations');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication failed: ${e.toString()}';
        _isAuthenticating = false;
      });
    }
  }

  /// Start OAuth flow by opening OpenRouter in an auth session
  Future<void> _startAuth() async {
    setState(() {
      _errorMessage = null;
      _isAuthenticating = true;
    });

    try {
      final authUrl = _openRouterService.startAuthFlow();
      final uri = Uri.parse(authUrl);
      final callbackUri = await launchAuthSession(
        uri,
        callbackUrlScheme: 'joey',
      );
      await _handleAuthCallback(callbackUri);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to start authentication: ${e.toString()}';
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _saveOpenAICompatibleConfig() async {
    setState(() {
      _errorMessage = null;
      _isAuthenticating = true;
    });

    try {
      final models = await _openRouterService.validateOpenAICompatibleConfig(
        baseUrl: _byoBaseUrlController.text.trim(),
        bearerToken: _byoTokenController.text.trim(),
        headers: _parseHeaders(_byoHeadersController.text),
      );
      if (models.isEmpty) {
        throw Exception('No models were returned by this API.');
      }
      await _openRouterService.saveOpenAICompatibleConfig(
        baseUrl: _byoBaseUrlController.text.trim(),
        bearerToken: _byoTokenController.text.trim(),
        headers: _parseHeaders(_byoHeadersController.text),
      );
      await _saveConsentState();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/conversations');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to validate API: ${e.toString()}';
          _isAuthenticating = false;
        });
      }
    }
  }

  Map<String, String> _parseHeaders(String text) {
    final headers = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final separator = trimmed.indexOf(':');
      if (separator <= 0) {
        throw FormatException('Invalid header line: $line');
      }
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        headers[key] = value;
      }
    }
    return headers;
  }

  void _openPrivacyPolicy() {
    launchInAppBrowser(
      Uri.parse(PrivacyConstants.privacyPolicyUrl),
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.chat_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to Joey',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Connect with OpenRouter or bring your own OpenAI-compatible API',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              SegmentedButton<_AuthProviderChoice>(
                segments: const [
                  ButtonSegment(
                    value: _AuthProviderChoice.openRouter,
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('OpenRouter'),
                  ),
                  ButtonSegment(
                    value: _AuthProviderChoice.openAICompatible,
                    icon: Icon(Icons.dns_outlined),
                    label: Text('OpenAI Compatible / BYO'),
                  ),
                ],
                selected: {_providerChoice},
                onSelectionChanged: _isAuthenticating
                    ? null
                    : (selection) {
                        setState(() {
                          _providerChoice = selection.first;
                          _errorMessage = null;
                        });
                      },
              ),
              const SizedBox(height: 16),

              // Data sharing disclosure
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Data Sharing Notice',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _providerChoice == _AuthProviderChoice.openAICompatible
                          ? 'By connecting, your conversation messages will be sent to the OpenAI-compatible API endpoint you configure, and to any MCP servers you configure for tool execution. Your data is stored locally on your device and is not collected by Joey.'
                          : 'By connecting, your conversation messages will be sent to OpenRouter for AI processing, and to any MCP servers you configure for tool execution. Your data is stored locally on your device and is not collected by Joey.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _openPrivacyPolicy,
                      child: Text(
                        'Read our Privacy Policy',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Consent checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _consentGiven,
                      onChanged: _isAuthenticating
                          ? null
                          : (bool? value) {
                              setState(() {
                                _consentGiven = value ?? false;
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isAuthenticating
                          ? null
                          : () {
                              setState(() {
                                _consentGiven = !_consentGiven;
                              });
                            },
                      child: Text(
                        'I understand and agree to the data sharing described above',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_providerChoice == _AuthProviderChoice.openAICompatible) ...[
                TextField(
                  controller: _byoBaseUrlController,
                  enabled: !_isAuthenticating,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _byoTokenController,
                  enabled: !_isAuthenticating,
                  decoration: const InputDecoration(
                    labelText: 'Bearer token (optional)',
                    hintText: 'sk-...',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _byoHeadersController,
                  enabled: !_isAuthenticating,
                  decoration: const InputDecoration(
                    labelText: 'Custom headers (optional)',
                    hintText: 'X-API-Key: value\nX-Custom: value',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
              ],

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Connect button
              FilledButton.icon(
                onPressed: (_isAuthenticating || !_consentGiven)
                    ? null
                    : _providerChoice == _AuthProviderChoice.openRouter
                    ? _startAuth
                    : _saveOpenAICompatibleConfig,
                icon: _isAuthenticating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _isAuthenticating
                      ? _providerChoice == _AuthProviderChoice.openAICompatible
                            ? 'Validating...'
                            : 'Connecting...'
                      : _providerChoice == _AuthProviderChoice.openRouter
                      ? 'Connect with OpenRouter'
                      : 'Validate & Save API',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              const SizedBox(height: 24),

              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _providerChoice == _AuthProviderChoice.openRouter
                              ? 'What is OpenRouter?'
                              : 'Bring your own API',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _providerChoice == _AuthProviderChoice.openRouter
                          ? 'OpenRouter provides access to multiple AI models through a single API. You\'ll be redirected to their website to authorize this app.'
                          : 'Use any API that implements OpenAI-compatible /models and /chat/completions endpoints. Joey validates the /models endpoint before saving.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
