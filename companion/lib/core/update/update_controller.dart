// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/update/release_manifest.dart';
import 'package:oui_spy/core/update/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, done, error }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.message = '',
    this.offer,
    this.fraction = 0,
  });

  final UpdatePhase phase;
  final String message;
  final UpdateOffer? offer;
  final double fraction;

  bool get busy => phase == UpdatePhase.checking || phase == UpdatePhase.downloading;
}

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._service, this._current) : super(const UpdateState());

  final UpdateService _service;
  final Future<AppVersion> Function() _current;

  Future<void> check({bool quiet = false}) async {
    if (state.busy) return;
    state = const UpdateState(phase: UpdatePhase.checking, message: 'Checking...');
    try {
      final current = await _current();
      final offer = await _service.check(current);
      if (offer == null) {
        state = UpdateState(phase: UpdatePhase.upToDate, message: 'Up to date ($current)');
      } else {
        state = UpdateState(
          phase: UpdatePhase.available,
          message: 'Version ${offer.version} is available',
          offer: offer,
        );
      }
    } catch (e) {
      final message = _describe(e);
      DebugLog.log('Update: check failed: $message');
      state = quiet ? const UpdateState() : UpdateState(phase: UpdatePhase.error, message: message);
    }
  }

  Future<void> install() async {
    final offer = state.offer;
    if (offer == null || state.busy) return;
    state = UpdateState(phase: UpdatePhase.downloading, message: 'Downloading...', offer: offer);
    try {
      final file = await _service.download(offer, onProgress: (got, total) {
        state = UpdateState(
          phase: UpdatePhase.downloading,
          message: 'Downloading ${(got * 100 ~/ total)}%',
          offer: offer,
          fraction: got / total,
        );
      });
      final result = await _service.install(file, offer);
      state = UpdateState(
        phase: UpdatePhase.done,
        offer: offer,
        message: switch (result.outcome) {
          InstallOutcome.installerOpened => 'Verified. Android is asking to install it.',
          InstallOutcome.needsPermission =>
            'Allow installs from this app in the Android settings that opened, then tap Install again.',
          InstallOutcome.savedToDownloads => 'Verified and saved to Downloads. Quit the app, then replace it.',
        },
      );
    } catch (e) {
      final message = _describe(e);
      DebugLog.log('Update: install failed: $message');
      state = UpdateState(phase: UpdatePhase.error, message: message, offer: offer);
    }
  }

  static String _describe(Object e) {
    if (e is ReleaseRefused) return e.message;
    if (e is GithubRateLimited) return e.toString();
    if (e is DioException) {
      final status = e.response?.statusCode;
      return status != null ? 'Update check failed: HTTP $status' : 'Update check failed: network error';
    }
    if (e is FileSystemException) return 'Update failed: ${e.message}';
    return 'Update failed: $e';
  }
}

class UpdateCheckAtLaunchNotifier extends StateNotifier<bool> {
  UpdateCheckAtLaunchNotifier(this._prefs) : super(_prefs.getBool(prefKey) ?? false);

  static const String prefKey = 'updateCheckAtLaunch';
  final SharedPreferences _prefs;

  Future<void> set(bool on) async {
    state = on;
    await _prefs.setBool(prefKey, on);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

Future<AppVersion> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  final v = AppVersion.tryParse(info.version, info.buildNumber);
  if (v == null) throw ReleaseRefused('this app has no readable version (${info.version}+${info.buildNumber})');
  return v;
}

final updateControllerProvider = StateNotifierProvider<UpdateController, UpdateState>(
  (ref) => UpdateController(ref.watch(updateServiceProvider), currentAppVersion),
);

final updateCheckAtLaunchProvider = StateNotifierProvider<UpdateCheckAtLaunchNotifier, bool>(
  (ref) => UpdateCheckAtLaunchNotifier(ref.watch(sharedPreferencesProvider)),
);
