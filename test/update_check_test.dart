import 'package:test/test.dart';
import 'package:virulja/ui/update_check.dart';

void main() {
  test('reads the build stamp of the script address', () {
    expect(buildOfScriptSrc('main.dart.js?v=123'), '123');
    expect(buildOfScriptSrc('main.dart.js'), isNull);
    expect(buildOfScriptSrc(null), isNull);
  });

  test('reloads only for a newer build', () {
    expect(
      updateNeeded(runningBuild: '200', cacheNames: ['virulja-100', 'virulja-200']),
      isFalse,
    );
    expect(
      updateNeeded(runningBuild: '200', cacheNames: ['virulja-200', 'virulja-300']),
      isTrue,
    );
  });

  test('reloads when in doubt', () {
    expect(updateNeeded(runningBuild: null, cacheNames: ['virulja-1']), isTrue);
    expect(updateNeeded(runningBuild: '1', cacheNames: const []), isTrue);
  });
}
