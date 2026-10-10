import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/domain.dart';

/// 在应用支持目录保存单条本地配置；不读取旧 Python 版本的凭据。
class LocalCredentialStore implements CredentialStore {
  LocalCredentialStore({this.directory, this.file});
  final Directory? directory;
  final File? file;
  static const fileName = 'credentials.json';

  Future<File> _resolveFile() async {
    if (file case final configuredFile?) return configuredFile;
    final directory = this.directory ?? await getApplicationSupportDirectory();
    return File('${directory.path}/$fileName');
  }

  @override
  Future<Credentials?> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['username'] is! String ||
          data['password'] is! String ||
          data['operatorSuffix'] is! String) {
        throw const AppFailure(FailureCode.credentialFileUnavailable);
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
      throw const AppFailure(FailureCode.credentialFileUnavailable);
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
      final file = await _resolveFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(value, flush: true);
      if (await file.readAsString() != value) {
        throw const AppFailure(FailureCode.credentialFileUnavailable);
      }
    } catch (_) {
      throw const AppFailure(FailureCode.credentialFileUnavailable);
    }
  }
}
