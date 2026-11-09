import 'dart:io';
import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late Directory directory;
  late File audio;
  const context = AiExtractionContext.fallback;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bee_audio_test_');
    audio = await File('${directory.path}/audio.wav').writeAsBytes([1]);
  });
  tearDown(() => directory.delete(recursive: true));

  test('speech API failure is not reported as no bookkeeping information',
      () async {
    final engine = DefaultAiExtractionEngine(
      speechRecognizer: (_) async => throw AIException('连接超时'),
      textCompleter: (_) async =>
          fail('Must not parse when transcription fails'),
    );
    await expectLater(
        engine.extractFromAudio(audio, context),
        throwsA(
          isA<AudioExtractionException>()
              .having((e) => e.message, 'stage', contains('语音转文字失败'))
              .having((e) => e.message, 'reason', contains('连接超时')),
        ));
  });

  test('text API failure preserves the transcription and failed stage',
      () async {
    final engine = DefaultAiExtractionEngine(
      speechRecognizer: (_) async => '早餐12元',
      textCompleter: (_) async => throw AIException('余额不足'),
    );
    await expectLater(
        engine.extractFromAudio(audio, context),
        throwsA(
          isA<AudioExtractionException>()
              .having((e) => e.recognizedText, 'transcription', '早餐12元')
              .having((e) => e.message, 'stage', contains('账单解析失败'))
              .having((e) => e.message, 'reason', contains('余额不足')),
        ));
    // Other text callers retain their existing empty-list contract.
    expect(await engine.extractFromText('早餐12元', context), isEmpty);
  });

  test('empty transcription gets a recording-specific error', () async {
    final engine =
        DefaultAiExtractionEngine(speechRecognizer: (_) async => '  ');
    await expectLater(
        engine.extractFromAudio(audio, context),
        throwsA(
          isA<AudioExtractionException>()
              .having((e) => e.message, 'reason', contains('没有识别到文字')),
        ));
  });

  test(
      'successful multi-bill extraction and valid empty response remain distinct',
      () async {
    final engine = DefaultAiExtractionEngine(
      speechRecognizer: (_) async => '早餐12元，收到报销200元',
      textCompleter: (_) async =>
          '[{"type":"expense","amount":-12},{"type":"income","amount":200}]',
    );
    final result = await engine.extractFromAudio(audio, context);
    expect(result.bills.map((bill) => bill.amount), [-12, 200]);
    expect(result.recognizedText, '早餐12元，收到报销200元');
    final empty = DefaultAiExtractionEngine(
        speechRecognizer: (_) async => '你好', textCompleter: (_) async => '[]');
    final noBills = await empty.extractFromAudio(audio, context);
    expect(noBills.bills, isEmpty);
    expect(noBills.recognizedText, '你好');
  });
}
