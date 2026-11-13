import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class UpdateFailure implements Exception {
  final String key;
  const UpdateFailure(this.key);
}

class InstalledApp {
  final String version, packageName, directory;
  final int code;
  final List<String> abis;
  final bool release;
  const InstalledApp(
    this.version,
    this.code,
    this.packageName,
    this.abis,
    this.directory,
    this.release,
  );
  factory InstalledApp.fromJson(Map<Object?, Object?> j) => InstalledApp(
    j['version'] as String,
    (j['code'] as num).toInt(),
    j['packageName'] as String,
    (j['abis'] as List).cast<String>(),
    j['directory'] as String,
    j['release'] == true,
  );
}

int compareVersions(String a, String b) {
  List<int> parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$',
    ).firstMatch(value);
    if (match == null) throw const UpdateFailure('updateInvalidRelease');
    return [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  }

  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final diff = x[i].compareTo(y[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

Uri releaseAssetUri(Object? value) {
  final uri = Uri.tryParse(value is String ? value : '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !uri.path.startsWith('/idlepoe/mosaic/releases/download/')) {
    throw const UpdateFailure('updateInvalidRelease');
  }
  return uri;
}

class AvailableUpdate {
  final String version, notes, name, hash;
  final int code, size;
  final Uri uri;
  const AvailableUpdate(
    this.version,
    this.notes,
    this.name,
    this.code,
    this.size,
    this.hash,
    this.uri,
  );

  static AvailableUpdate? parse(
    Map<String, dynamic> release,
    Map<String, dynamic> manifest,
    InstalledApp installed,
  ) {
    if (manifest['schema'] != 1 ||
        manifest['packageName'] != installed.packageName ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      throw const UpdateFailure('updateInvalidRelease');
    }
    final version = manifest['version'] as String;
    if (compareVersions(version, release['tag_name'] as String) != 0) {
      throw const UpdateFailure('updateInvalidRelease');
    }
    if (compareVersions(version, installed.version) < 0) return null;
    final packages = (manifest['apks'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? apk;
    for (final abi in [...installed.abis, 'universal']) {
      for (final item in packages) {
        if (item['abi'] == abi) {
          apk = item;
          break;
        }
      }
      if (apk != null) break;
    }
    if (apk == null) throw const UpdateFailure('updateNoCompatibleApk');
    final code = (apk['versionCode'] as num).toInt();
    if (code <= installed.code) return null;
    final hash = apk['sha256'] as String;
    final name = apk['asset'] as String;
    final size = (apk['size'] as num).toInt();
    if (!RegExp(r'^[a-zA-Z0-9_.-]+\.apk$').hasMatch(name) ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        size <= 0 ||
        size > 1024 * 1024 * 1024) {
      throw const UpdateFailure('updateInvalidRelease');
    }
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final matching = assets.where((item) => item['name'] == name).toList();
    if (matching.length != 1 || matching.single['size'] != size) {
      throw const UpdateFailure('updateInvalidRelease');
    }
    return AvailableUpdate(
      version,
      release['body'] as String? ?? '',
      name,
      code,
      size,
      hash.toLowerCase(),
      releaseAssetUri(matching.single['browser_download_url']),
    );
  }
}

abstract interface class UpdateTransport {
  Future<Stream<List<int>>> open(Uri uri);
  void close();
}

class GithubTransport implements UpdateTransport {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  @override
  Future<Stream<List<int>>> open(Uri uri) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      final host = uri.host;
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          !(host == 'api.github.com' ||
              host == 'github.com' ||
              host.endsWith('.githubusercontent.com'))) {
        throw const UpdateFailure('updateInvalidRelease');
      }
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set('User-Agent', 'Mosaic-Android-Updater');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().timeout(const Duration(seconds: 30));
        if (location == null) throw const UpdateFailure('updateNetworkError');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throw const UpdateFailure('updateNetworkError');
      }
      return response.timeout(const Duration(seconds: 30));
    }
    throw const UpdateFailure('updateNetworkError');
  }

  @override
  void close() => _client.close(force: true);
}

class UpdateClient {
  final UpdateTransport transport;
  bool _cancelled = false;
  UpdateClient(this.transport);
  void cancel() {
    _cancelled = true;
    transport.close();
  }

  void close() => transport.close();
  void _checkCancelled() {
    if (_cancelled) throw const UpdateFailure('updateCancelled');
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final bytes = <int>[];
    await for (final chunk in await transport.open(uri)) {
      _checkCancelled();
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const UpdateFailure('updateInvalidRelease');
      }
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<AvailableUpdate?> check(InstalledApp installed) async {
    final release = await _json(
      Uri.https('api.github.com', '/repos/idlepoe/mosaic/releases/latest'),
    );
    if (release['draft'] == true || release['prerelease'] == true) return null;
    if (compareVersions(release['tag_name'] as String, installed.version) < 0) {
      return null;
    }
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final manifests = assets
        .where((asset) => asset['name'] == 'mosaic-update.json')
        .toList();
    if (manifests.isEmpty &&
        compareVersions(release['tag_name'] as String, installed.version) ==
            0) {
      return null;
    }
    if (manifests.length != 1) {
      throw const UpdateFailure('updateInvalidRelease');
    }
    final manifest = await _json(
      releaseAssetUri(manifests.single['browser_download_url']),
    );
    return AvailableUpdate.parse(release, manifest, installed);
  }

  Future<File> download(
    AvailableUpdate update,
    Directory directory,
    void Function(int received, int total) progress,
  ) async {
    await directory.create(recursive: true);
    // A private, fixed basename prevents release metadata from choosing a path.
    final partial = File('${directory.path}/update.apk.part');
    final complete = File('${directory.path}/update.apk');
    if (await complete.exists()) await complete.delete();
    var received = 0;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final output = await partial.open(mode: FileMode.write);
    try {
      _checkCancelled();
      await for (final chunk in await transport.open(update.uri)) {
        _checkCancelled();
        received += chunk.length;
        if (received > update.size) {
          throw const UpdateFailure('updateVerificationFailed');
        }
        await output.writeFrom(chunk);
        hasher.add(chunk);
        progress(received, update.size);
      }
      _checkCancelled();
      hasher.close();
      if (received != update.size || digest.value.toString() != update.hash) {
        throw const UpdateFailure('updateVerificationFailed');
      }
      await output.close();
      return await partial.rename(complete.path);
    } catch (_) {
      await output.close();
      if (await partial.exists()) await partial.delete();
      _checkCancelled();
      rethrow;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
