import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/domain.dart';

/// 单条系统安全存储记录；不读取旧 Python 版本的凭据。
class SystemCredentialStore implements CredentialStore {
  SystemCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  static const recordKey = 'xduwlan.gui.credentials.v1';

  @override
  Future<Credentials?> load() async {
    try {
      final raw = await _storage.read(key: recordKey);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['username'] is! String ||
          data['password'] is! String ||
          data['operatorSuffix'] is! String) {
        throw const AppFailure(FailureCode.credentialStoreUnavailable);
      }
      final credentials = Credentials(
        data['username'] as String,
        data['password'] as String,
        operatorSuffix: data['operatorSuffix'] as String,
      );
      validateCredentials(credentials);
      return credentials;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(FailureCode.credentialStoreUnavailable);
    }
  }

  @override
  Future<void> save(Credentials credentials) async {
    validateCredentials(credentials);
    try {
      final value = jsonEncode({
        'username': credentials.username,
        'password': credentials.password,
        'operatorSuffix': credentials.operatorSuffix,
      });
      await _storage.write(key: recordKey, value: value);
      if (await _storage.read(key: recordKey) != value) {
        throw const AppFailure(FailureCode.credentialStoreUnavailable);
      }
    } catch (_) {
      throw const AppFailure(FailureCode.credentialStoreUnavailable);
    }
  }
}
