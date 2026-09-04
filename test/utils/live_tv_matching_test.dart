import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/utils/live_tv_matching.dart';

void main() {
  test('matches channel by id and server', () {
    final program = LiveTvProgram(title: 'News', channelIdentifier: '101', serverId: 'server-a');

    expect(liveTvProgramMatchesChannel(program, LiveTvChannel(key: '101', serverId: 'server-a')), isTrue);
    expect(liveTvProgramMatchesChannel(program, LiveTvChannel(key: '101', serverId: 'server-b')), isFalse);
  });

  test('matches channel identifier fallback', () {
    final program = LiveTvProgram(title: 'News', channelIdentifier: 'station-101', serverId: 'server-a');
    final channel = LiveTvChannel(key: '101', identifier: 'station-101', serverId: 'server-a');

    expect(liveTvProgramMatchesChannel(program, channel), isTrue);
  });

  test('uses provider identifier when duplicate channels exist on one server', () {
    final program = LiveTvProgram(
      title: 'News',
      channelIdentifier: '101',
      serverId: 'server-a',
      providerIdentifier: 'provider-a',
    );

    final matching = LiveTvChannel(key: '101', serverId: 'server-a', favoriteSource: 'server://machine/provider-a');
    final otherProvider = LiveTvChannel(
      key: '101',
      serverId: 'server-a',
      favoriteSource: 'server://machine/provider-b',
    );

    expect(liveTvProgramMatchesChannel(program, matching), isTrue);
    expect(liveTvProgramMatchesChannel(program, otherProvider), isFalse);
  });

  test('target-channel resolution qualifies duplicate IDs by server and DVR', () {
    final channels = [
      LiveTvChannel(key: '7', serverId: 'server-a', liveDvrKey: 'dvr-a'),
      LiveTvChannel(key: '7', serverId: 'server-b', liveDvrKey: 'dvr-b'),
    ];

    expect(liveTvChannelIndexByScope(channels, channels[1]), 1);
    expect(
      liveTvChannelIndexByScope(channels, LiveTvChannel(key: '7', serverId: 'server-a', liveDvrKey: 'missing-dvr')),
      -1,
    );
  });
}
