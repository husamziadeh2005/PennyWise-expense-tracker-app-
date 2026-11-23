import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/core/network/api_client.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The "Try again" screen: when the API server is down the app must keep
/// retrying on its own and recover as soon as the server is up.
void main() {
  test('retries automatically while the API is unreachable, then recovers', () {
    fakeAsync((async) {
      var serverUp = false;
      var calls = 0;
      ApiClient.instance.tokenOverride = ({bool forceRefresh = false}) async => 'test-token';
      ApiClient.instance.httpClient = MockClient((req) async {
        calls++;
        if (!serverUp) throw const SocketException('Connection refused');
        final body = req.url.path == '/api/auth/me'
            ? {'profile': {'id': 'u1', 'fullName': 'A', 'currency': 'JOD'}, 'features': {}}
            : {'items': []};
        return http.Response(jsonEncode(body), 200);
      });

      final state = AppState.instance;
      state.start(realtime: false);
      async.flushMicrotasks();

      expect(state.loadError, contains('Cannot reach the server'));
      expect(state.loadErrorIsNetwork, isTrue);

      // Still down: another attempt after the retry delay.
      final before = calls;
      async.elapse(AppState.retryEvery);
      expect(calls, greaterThan(before));
      expect(state.loadError, isNotNull);

      // Server comes up -> next automatic retry succeeds, no tap needed.
      serverUp = true;
      async.elapse(AppState.retryEvery);
      expect(state.loadError, isNull);
      expect(state.loadErrorIsNetwork, isFalse);
      expect(state.profile?.id, 'u1');

      state.stop();
      async.flushMicrotasks();
    });
  });

  test('does not auto-retry real API errors (e.g. 500)', () {
    fakeAsync((async) {
      var calls = 0;
      ApiClient.instance.tokenOverride = ({bool forceRefresh = false}) async => 'test-token';
      ApiClient.instance.httpClient = MockClient((req) async {
        calls++;
        return http.Response('{"error":{"code":"internal","message":"Boom."}}', 500);
      });
      final state = AppState.instance;
      state.start(realtime: false);
      async.flushMicrotasks();
      final after = calls;
      expect(state.loadErrorIsNetwork, isFalse);
      async.elapse(AppState.retryEvery * 3);
      expect(calls, after);
      state.stop();
      async.flushMicrotasks();
    });
  });
}
