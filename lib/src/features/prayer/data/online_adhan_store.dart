import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/local_settings.dart';
import '../domain/models/online_adhan.dart';

/// Which downloaded muezzin (if any) replaces the bundled adhan voice.
class OnlineAdhanSelection {
  final String? generalId;
  final String? fajrId;
  final Set<String> downloaded;

  const OnlineAdhanSelection({
    this.generalId,
    this.fajrId,
    this.downloaded = const {},
  });

  OnlineAdhanSelection copyWith({
    String? generalId,
    String? fajrId,
    bool clearGeneral = false,
    bool clearFajr = false,
    Set<String>? downloaded,
  }) {
    return OnlineAdhanSelection(
      generalId: clearGeneral ? null : (generalId ?? this.generalId),
      fajrId: clearFajr ? null : (fajrId ?? this.fajrId),
      downloaded: downloaded ?? this.downloaded,
    );
  }
}

/// Downloads muezzin recordings once and tells the native alarm which local
/// file to play. When no downloaded muezzin is selected (or its file is
/// missing) the native alarm keeps using the bundled voices.
class OnlineAdhanStore extends StateNotifier<OnlineAdhanSelection> {
  static const _generalKey = 'adhan.online.general';
  static const _fajrKey = 'adhan.online.fajr';
  static const MethodChannel _channel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  OnlineAdhanStore()
      : super(OnlineAdhanSelection(
          generalId: _nonEmpty(LocalSettings.getString(_generalKey)),
          fajrId: _nonEmpty(LocalSettings.getString(_fajrKey)),
        )) {
    unawaited(refresh());
  }

  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

  final Map<String, double> _progress = {};

  /// Download progress 0..1 for an adhan currently downloading.
  double? progressOf(String id) => _progress[id];

  Future<Directory?> _dir() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/adhans');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<File?> fileFor(OnlineAdhan adhan) async {
    final dir = await _dir();
    if (dir == null) return null;
    return File('${dir.path}/${adhan.fileName}');
  }

  /// Re-reads which files exist and re-syncs the native alarm.
  Future<void> refresh() async {
    final found = <String>{};
    for (final a in OnlineAdhan.all) {
      final f = await fileFor(a);
      if (f != null && await f.exists() && await f.length() > 10 * 1024) {
        found.add(a.id);
      }
    }
    if (!mounted) return;
    state = state.copyWith(downloaded: found);
    await _syncNative();
  }

  /// Downloads [adhan]; [onProgress] receives 0..1. Throws on failure.
  Future<void> download(
    OnlineAdhan adhan, {
    void Function(double)? onProgress,
  }) async {
    final target = await fileFor(adhan);
    if (target == null) throw const FileSystemException('storage unavailable');
    final tmp = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(adhan.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = received / total;
          _progress[adhan.id] = p;
          onProgress?.call(p);
        }
      }
      await sink.close();
      if (received < 10 * 1024) {
        throw const FileSystemException('download too small');
      }
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    } finally {
      _progress.remove(adhan.id);
      client.close(force: true);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
    await refresh();
  }

  Future<void> delete(OnlineAdhan adhan) async {
    final f = await fileFor(adhan);
    if (f != null && await f.exists()) await f.delete();
    if (state.generalId == adhan.id) await selectGeneral(null);
    if (state.fajrId == adhan.id) await selectFajr(null);
    await refresh();
  }

  Future<void> selectGeneral(String? id) async {
    LocalSettings.setString(_generalKey, id ?? '');
    state = state.copyWith(generalId: id, clearGeneral: id == null);
    await _syncNative();
  }

  Future<void> selectFajr(String? id) async {
    LocalSettings.setString(_fajrKey, id ?? '');
    state = state.copyWith(fajrId: id, clearFajr: id == null);
    await _syncNative();
  }

  Future<String?> _pathIfDownloaded(String? id) async {
    final a = OnlineAdhan.byId(id);
    if (a == null || !state.downloaded.contains(a.id)) return null;
    final f = await fileFor(a);
    return f?.path;
  }

  Future<void> _syncNative() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setCustomAdhanFiles', {
        'general': await _pathIfDownloaded(state.generalId),
        'fajr': await _pathIfDownloaded(state.fajrId),
      });
    } catch (_) {
      // Older native side or tests: bundled voices remain in use.
    }
  }
}

final onlineAdhanStoreProvider =
    StateNotifierProvider<OnlineAdhanStore, OnlineAdhanSelection>(
  (ref) => OnlineAdhanStore(),
);
