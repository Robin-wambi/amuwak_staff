import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/sync/sync_failure_policy.dart';

void main() {
  group('isTransientSyncError', () {
    test('treats socket / timeout / client transport errors as transient', () {
      expect(isTransientSyncError(SocketException('failed host lookup')),
          isTrue);
      expect(isTransientSyncError(TimeoutException('slow')), isTrue);
      expect(
          isTransientSyncError(
              Exception('ClientException: Connection closed before full header')),
          isTrue);
      expect(
          isTransientSyncError('Connection refused (os error 111)'),
          isTrue);
    });

    test('treats a Postgrest data rejection as NON-transient', () {
      expect(
          isTransientSyncError(
              const PostgrestException(message: 'duplicate key', code: '23505')),
          isFalse);
    });

    test('treats an unknown-op StateError as NON-transient', () {
      expect(isTransientSyncError(StateError('unknown op "frobnicate"')),
          isFalse);
    });
  });

  group('friendlySyncError', () {
    test('maps null / empty to a generic line', () {
      expect(friendlySyncError(null), 'Could not be saved.');
      expect(friendlySyncError('   '), 'Could not be saved.');
    });

    test('maps known Postgres codes to plain language', () {
      expect(friendlySyncError('23505: duplicate key value'),
          'Already saved on the server.');
      expect(friendlySyncError('23503: violates foreign key constraint'),
          'Linked record is missing on the server.');
      expect(friendlySyncError('new row violates row-level security policy'),
          'Not allowed on the server (permissions).');
      expect(friendlySyncError('JWT expired'),
          'Sign-in expired — sign out and back in.');
    });

    test('maps transport text to a retry message', () {
      expect(friendlySyncError('SocketException: failed host lookup'),
          'Connection problem — will retry automatically.');
    });

    test('falls back to a server-rejected line', () {
      expect(friendlySyncError('42P01: relation does not exist'),
          'Could not be saved (server rejected it).');
    });
  });
}
