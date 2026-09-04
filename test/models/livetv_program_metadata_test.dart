import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_program.dart';

void main() {
  test('Plex program parses content rating, premiere status, and original air date', () {
    final program = LiveTvProgram.fromJson({
      'title': 'Pilot',
      'contentRating': 'TV-14',
      'premiere': true,
      'originallyAvailableAt': '2026-08-30',
    });

    expect(program.contentRating, 'TV-14');
    expect(program.airingStatus, LiveTvAiringStatus.premiere);
    expect(program.originalAirDate, DateTime(2026, 8, 30));
  });

  test('false Plex premiere flag remains unknown rather than becoming a rerun', () {
    final program = LiveTvProgram.fromJson({'title': 'News', 'premiere': false});

    expect(program.premiere, isFalse);
    expect(program.airingStatus, LiveTvAiringStatus.unknown);
  });

  test('Plex only labels explicit new and rerun signals', () {
    expect(LiveTvProgram.fromJson({'title': 'New episode', 'new': true}).airingStatus, LiveTvAiringStatus.newEpisode);
    expect(LiveTvProgram.fromJson({'title': 'Repeat', 'repeat': true}).airingStatus, LiveTvAiringStatus.rerun);
  });
}
