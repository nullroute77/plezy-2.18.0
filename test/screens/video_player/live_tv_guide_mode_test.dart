import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_capture_buffer.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/screens/livetv/live_tv_guide_layout.dart';
import 'package:plezy/screens/video_player/live_tv_session_args.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/mock_player_channels.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('guide transitions retain the same player and session owner without transport teardown', (tester) async {
    final nativeInitialize = Completer<bool>();
    final fakePlayer = _LifecycleCountingPlayer();

    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) => call.method == 'initialize' ? nativeInitialize.future : Future<Object?>.value(),
      testBody: () async {
        final key = GlobalKey<VideoPlayerScreenState>();
        final channel = LiveTvChannel(key: 'duplicate-id', serverId: 'server-a', liveDvrKey: 'dvr-a');
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => PlaybackStateProvider(),
            child: MaterialApp(
              home: VideoPlayerScreen(
                key: key,
                metadata: testMediaItem(title: 'Live TV'),
                live: LiveTvSessionArgs(channel: channel, channels: [channel], currentChannelIndex: 0),
              ),
            ),
          ),
        );
        final state = key.currentState!;
        state.player = fakePlayer;
        final sessionOwner = state.liveTvSessionStateIdentityForTesting;

        await state.handleLiveTvBackForTesting();
        await tester.pump();
        expect(state.liveTvViewMode, LiveTvViewMode.guide);
        expect(state.player, same(fakePlayer));
        expect(state.liveTvSessionStateIdentityForTesting, same(sessionOwner));
        expect(fakePlayer.pauseCalls, 0);
        expect(fakePlayer.stopCalls, 0);
        expect(fakePlayer.disposeCalls, 0);

        await state.handleLiveTvBackForTesting();
        await tester.pump();
        expect(state.liveTvViewMode, LiveTvViewMode.fullscreen);
        expect(state.player, same(fakePlayer));
        expect(state.liveTvSessionStateIdentityForTesting, same(sessionOwner));
        expect(fakePlayer.pauseCalls, 0);
        expect(fakePlayer.stopCalls, 0);
        expect(fakePlayer.disposeCalls, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        nativeInitialize.complete(true);
        await tester.pump();
      },
    );
  });

  testWidgets('target channel selection replaces the stream in place using qualified identity', (tester) async {
    final nativeInitialize = Completer<bool>();
    final fakePlayer = _LifecycleCountingPlayer();
    final liveTv = _SwitchingLiveTvSupport();
    final client = _SwitchingMediaServerClient(liveTv);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = testMultiServerProvider(manager)
      ..debugSetLiveTvServersForTesting([LiveTvServerInfo(serverId: 'server-b', dvrKey: 'dvr-b')]);
    addTearDown(() {
      multiServer.dispose();
      manager.dispose();
    });

    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) => call.method == 'initialize' ? nativeInitialize.future : Future<Object?>.value(),
      testBody: () async {
        final key = GlobalKey<VideoPlayerScreenState>();
        final current = LiveTvChannel(key: 'duplicate-id', serverId: 'server-a', liveDvrKey: 'dvr-a');
        final target = LiveTvChannel(key: 'duplicate-id', serverId: 'server-b', liveDvrKey: 'dvr-b');
        await tester.pumpWidget(
          ChangeNotifierProvider<MultiServerProvider>.value(
            value: multiServer,
            child: ChangeNotifierProvider(
              create: (_) => PlaybackStateProvider(),
              child: MaterialApp(
                home: VideoPlayerScreen(
                  key: key,
                  metadata: testMediaItem(title: 'Live TV'),
                  live: LiveTvSessionArgs(channel: current, channels: [current, target], currentChannelIndex: 0),
                ),
              ),
            ),
          ),
        );
        final state = key.currentState!;
        state.player = fakePlayer;

        await state.switchLiveTvChannelForTesting(
          LiveTvChannel(key: 'duplicate-id', serverId: 'server-b', liveDvrKey: 'dvr-b'),
        );
        await tester.pump();

        expect(state.player, same(fakePlayer));
        expect(state.liveTvChannelIndexForTesting, 1);
        expect(fakePlayer.openCalls, 1);
        expect(liveTv.startedChannels, ['duplicate-id']);
        expect(liveTv.startedDvrKeys, ['dvr-b']);

        // Let the one-shot initial heartbeat run; route disposal cancels the
        // periodic timer that remains after it.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(const SizedBox.shrink());
        nativeInitialize.complete(true);
        await tester.pump();
      },
    );
  });

  testWidgets('explicit Live TV exit reports stopped and disposes the active player', (tester) async {
    final nativeInitialize = Completer<bool>();
    final fakePlayer = _LifecycleCountingPlayer();
    final liveSession = _SwitchingLiveTvSession();
    final playerKey = GlobalKey<VideoPlayerScreenState>();

    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) => call.method == 'initialize' ? nativeInitialize.future : Future<Object?>.value(),
      testBody: () async {
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => PlaybackStateProvider(),
            child: MaterialApp(
              home: VideoPlayerScreen(
                key: playerKey,
                metadata: testMediaItem(title: 'Live TV'),
                live: LiveTvSessionArgs(
                  channel: LiveTvChannel(key: 'channel-a', serverId: 'server-a', liveDvrKey: 'dvr-a'),
                ),
              ),
            ),
          ),
        );

        final state = playerKey.currentState!;
        state.player = fakePlayer;
        state.adoptLiveTvSessionForTesting(liveSession);
        await state.sendStoppedLiveTvProgressForTesting();
        await tester.pumpWidget(const SizedBox.shrink());

        expect(liveSession.reportedStates, contains('stopped'));
        expect(fakePlayer.disposeCalls, 1);

        nativeInitialize.complete(true);
        await tester.pump();
      },
    );
  });
}

class _LifecycleCountingPlayer implements Player {
  _LifecycleCountingPlayer({bool playing = false})
    : _state = PlayerState(playing: playing, position: Duration.zero, duration: Duration.zero, seekable: false);

  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  int openCalls = 0;
  final PlayerState _state;

  @override
  PlayerState get state => _state;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> open(
    Media media, {
    bool play = true,
    bool isLive = false,
    List<SubtitleTrack>? externalSubtitles,
    Duration? timelineDuration,
  }) async {
    openCalls++;
  }

  @override
  Future<void> setProperty(String name, String value) async {}

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async => disposeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchingMediaServerClient implements MediaServerClient {
  _SwitchingMediaServerClient(this.liveTv);

  @override
  final _SwitchingLiveTvSupport liveTv;

  @override
  ServerId get serverId => ServerId('server-b');

  @override
  String get serverName => 'Server B';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(liveTv: true);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchingLiveTvSupport implements LiveTvSupport {
  final List<String> startedChannels = [];
  final List<String?> startedDvrKeys = [];

  @override
  Future<LiveTvPlaybackSession?> startPlayback(String channelKey, {String? dvrKey}) async {
    startedChannels.add(channelKey);
    startedDvrKeys.add(dvrKey);
    return _SwitchingLiveTvSession();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchingLiveTvSession implements LiveTvPlaybackSession {
  final List<String> reportedStates = [];

  @override
  LiveProgramInfo get program => const LiveProgramInfo();

  @override
  LiveTvBackgroundPolicy get backgroundPolicy => LiveTvBackgroundPolicy.retainSession;

  @override
  CaptureBuffer? get captureBuffer => null;

  @override
  List<MediaSubtitleTrack> get subtitleTracks => const [];

  @override
  bool get canTimeShift => false;

  @override
  Future<String?> streamUrlAt({int? offsetSeconds, MediaSubtitleTrack? subtitleTrack}) async =>
      'https://example.test/live.m3u8';

  @override
  Future<CaptureBuffer?> reportTimeline({
    required String state,
    required int positionMs,
    required int durationMs,
  }) async {
    reportedStates.add(state);
    return null;
  }

  @override
  Future<LiveTvPlaybackSession?> recover({required bool directStream, required bool directStreamAudio}) async => this;
}
