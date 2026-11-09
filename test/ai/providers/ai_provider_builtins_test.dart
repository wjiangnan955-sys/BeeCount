import 'dart:convert';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh installs and reloads never supply embedded API keys', () async {
    expect(AIServiceProviderConfig.builtInDefaults.every((p) => p.apiKey.isEmpty), isTrue);
    for (var load = 0; load < 2; load++) {
      final providers = await AIProviderManager.getProviders();
      expect(providers.every((p) => p.apiKey.isEmpty), isTrue);
    }
  });

  test('fresh setup includes DeepSeek as a protected text preset', () async {
    final providers = await AIProviderManager.getProviders();
    final deepseek = providers.singleWhere((p) => p.id == 'deepseek');
    expect(deepseek.isBuiltIn, isTrue);
    expect(deepseek.usesZhipuSdk, isFalse);
    expect(deepseek.baseUrl, 'https://api.deepseek.com');
    expect(deepseek.textModel, 'deepseek-flash');
    expect(deepseek.supportsSpeech, isFalse);
    expect(await AIProviderManager.deleteProvider(deepseek.id), isFalse);
  });

  test('upgrade adds DeepSeek once and preserves keys, models and bindings',
      () async {
    final glm = AIServiceProviderConfig.zhipuDefault
        .copyWith(apiKey: 'existing-test-key', textModel: 'existing-model');
    final custom = AIServiceProviderConfig(
        id: 'custom',
        name: 'My provider',
        apiKey: 'custom-test-key',
        baseUrl: 'https://example.com/v1',
        textModel: 'custom-model',
        createdAt: DateTime(2026));
    SharedPreferences.setMockInitialValues({
      'ai_providers_v2': jsonEncode([glm.toJson(), custom.toJson()]),
      'ai_capability_binding_v2': jsonEncode(
          const AICapabilityBinding(textProviderId: 'custom').toJson()),
    });
    await AIProviderManager.getProviders();
    final providers = await AIProviderManager.getProviders();
    expect(providers.where((p) => p.id == 'deepseek'), hasLength(1));
    expect(providers.firstWhere((p) => p.id == glm.id).toJson(), glm.toJson());
    expect(providers.firstWhere((p) => p.id == custom.id).toJson(),
        custom.toJson());
    expect((await AIProviderManager.getCapabilityBinding()).textProviderId,
        'custom');
  });

  test('reload preserves the user edited DeepSeek config', () async {
    await AIProviderManager.getProviders();
    final edited = AIServiceProviderConfig.deepseekDefault
        .copyWith(apiKey: 'edited-test-key', textModel: 'my-model');
    await AIProviderManager.updateProvider(edited);
    expect((await AIProviderManager.getProvider('deepseek'))!.toJson(),
        edited.toJson());
  });
}
