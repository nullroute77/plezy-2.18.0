import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../../utils/live_tv_matching.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/optimized_media_image.dart';
import 'livetv_styles.dart';
import 'tabs/guide_tab.dart';

/// The two presentations owned by one Live TV player route.
enum LiveTvViewMode { fullscreen, guide }

/// Shared information-first Live TV guide used by both the browse screen and
/// the still-playing guide presentation inside [VideoPlayerScreen].
class LiveTvGuideLayout extends StatefulWidget {
  static const double previewInset = 16;

  final GlobalKey<GuideTabState>? guideKey;
  final List<LiveTvChannel> channels;
  final bool Function(LiveTvChannel channel)? isFavoriteChannel;
  final void Function(LiveTvChannel channel)? onToggleFavorite;
  final Future<void> Function(LiveTvChannel channel)? onTuneChannel;
  final ValueChanged<LiveTvProgram?>? onProgramFocused;
  final String? playingChannelScopeKey;
  final bool hasActivePlayback;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onBack;
  final VoidCallback? onStopPlayback;

  const LiveTvGuideLayout({
    super.key,
    this.guideKey,
    required this.channels,
    this.isFavoriteChannel,
    this.onToggleFavorite,
    this.onTuneChannel,
    this.onProgramFocused,
    this.playingChannelScopeKey,
    this.hasActivePlayback = false,
    this.onNavigateUp,
    this.onBack,
    this.onStopPlayback,
  });

  static double informationHeightFor(Size size) {
    if (size.width < 700) return (size.height * 0.28).clamp(150.0, 180.0);
    return (size.height * 0.43).clamp(250.0, 310.0);
  }

  static Size previewSizeFor(Size size) {
    final availableHeight = informationHeightFor(size) - previewInset * 2;
    final maxWidth = size.width < 700 ? size.width * 0.42 : size.width * 0.34;
    final width = (availableHeight * 16 / 9).clamp(0.0, maxWidth);
    return Size(width, width * 9 / 16);
  }

  static Rect previewRectFor(Size size, TextDirection direction) {
    final preview = previewSizeFor(size);
    final left = direction == TextDirection.ltr ? size.width - previewInset - preview.width : previewInset;
    return Rect.fromLTWH(left, previewInset, preview.width, preview.height);
  }

  @override
  State<LiveTvGuideLayout> createState() => _LiveTvGuideLayoutState();
}

class _LiveTvGuideLayoutState extends State<LiveTvGuideLayout> {
  static const _artworkDebounce = Duration(milliseconds: 140);

  LiveTvProgram? _focusedProgram;
  LiveTvProgram? _artworkProgram;
  Timer? _artworkTimer;
  final FocusNode _stopFocusNode = FocusNode(debugLabel: 'live_tv_stop');

  @override
  void dispose() {
    _artworkTimer?.cancel();
    _stopFocusNode.dispose();
    super.dispose();
  }

  void _handleProgramFocused(LiveTvProgram? program) {
    if (!identical(program, _focusedProgram)) {
      setState(() => _focusedProgram = program);
    }
    widget.onProgramFocused?.call(program);

    _artworkTimer?.cancel();
    if (program?.thumb == null || program!.thumb!.isEmpty) {
      if (_artworkProgram != null) setState(() => _artworkProgram = null);
      return;
    }
    _artworkTimer = Timer(_artworkDebounce, () {
      if (mounted && identical(_focusedProgram, program)) {
        setState(() => _artworkProgram = program);
      }
    });
  }

  LiveTvChannel? _channelFor(LiveTvProgram? program) {
    if (program == null) return null;
    return widget.channels.where((channel) => liveTvProgramMatchesChannel(program, channel)).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final direction = Directionality.of(context);
        final previewRect = widget.hasActivePlayback ? LiveTvGuideLayout.previewRectFor(size, direction) : null;
        final informationHeight = LiveTvGuideLayout.informationHeightFor(size);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GuideBackdropPainter(color: Theme.of(context).scaffoldBackgroundColor, hole: previewRect),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: informationHeight,
                  child: _ProgramInformation(
                    program: _focusedProgram,
                    artworkProgram: _artworkProgram,
                    channel: _channelFor(_focusedProgram),
                    trailingSpace: previewRect?.width ?? 0,
                    onStopPlayback: widget.onStopPlayback,
                    stopFocusNode: _stopFocusNode,
                  ),
                ),
                Expanded(
                  child: GuideTab(
                    key: widget.guideKey,
                    channels: widget.channels,
                    isFavoriteChannel: widget.isFavoriteChannel,
                    onToggleFavorite: widget.onToggleFavorite,
                    onTuneChannel: widget.onTuneChannel,
                    onProgramFocused: _handleProgramFocused,
                    playingChannelScopeKey: widget.playingChannelScopeKey,
                    backReturnsImmediately: widget.hasActivePlayback,
                    onNavigateUp:
                        widget.onNavigateUp ??
                        (widget.onStopPlayback == null ? null : () => _stopFocusNode.requestFocus()),
                    onBack: widget.onBack,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProgramInformation extends StatelessWidget {
  final LiveTvProgram? program;
  final LiveTvProgram? artworkProgram;
  final LiveTvChannel? channel;
  final double trailingSpace;
  final VoidCallback? onStopPlayback;
  final FocusNode stopFocusNode;

  const _ProgramInformation({
    required this.program,
    required this.artworkProgram,
    required this.channel,
    required this.trailingSpace,
    required this.onStopPlayback,
    required this.stopFocusNode,
  });

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final item = program;
    final poster = _nonEmpty(artworkProgram?.thumb);
    final isEpisode = _nonEmpty(item?.grandparentTitle) != null;
    final primaryTitle = isEpisode ? item!.grandparentTitle! : item?.title;
    final secondaryTitle = isEpisode ? _nonEmpty(item?.title) : null;
    final channelName = channel?.displayName ?? _nonEmpty(item?.channelCallSign);
    final seasonEpisode = item == null
        ? null
        : item.parentIndex != null && item.index != null
        ? 'S${item.parentIndex} E${item.index}'
        : item.index != null
        ? 'E${item.index}'
        : null;
    final metadata = <String>[
      ?seasonEpisode,
      ?_nonEmpty(item?.contentRating),
      if (item?.year != null) '${item!.year}',
      if ((item?.durationMinutes ?? 0) > 0) formatDurationTextual(item!.durationMinutes * 60_000),
    ];
    final airing = <String>[
      ?channelName,
      if (item?.startTime != null)
        item!.endTime == null
            ? formatClockTime(item.startTime!, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context))
            : '${formatClockTime(item.startTime!, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context))}–${formatClockTime(item.endTime!, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context))}',
    ];

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        LiveTvGuideLayout.previewInset,
        12,
        LiveTvGuideLayout.previewInset + trailingSpace + (trailingSpace > 0 ? 16 : 0),
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (poster != null) ...[
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tk.radiusSm),
                child: OptimizedMediaImage.poster(
                  key: ValueKey(poster),
                  client: _clientFor(context, artworkProgram),
                  imagePath: poster,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: item == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              primaryTitle ?? item.title,
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (onStopPlayback != null)
                            IconButton(
                              focusNode: stopFocusNode,
                              onPressed: onStopPlayback,
                              tooltip: 'Stop Live TV',
                              icon: const AppIcon(Symbols.stop_circle_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (secondaryTitle != null)
                        Text(
                          secondaryTitle,
                          style: theme.textTheme.titleMedium?.copyWith(color: tk.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (item.airingStatus != LiveTvAiringStatus.unknown)
                            StatusPill(label: _airingStatusLabel(item.airingStatus), color: theme.colorScheme.primary),
                          if (metadata.isNotEmpty)
                            Text(metadata.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted)),
                        ],
                      ),
                      if (airing.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          airing.join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (_nonEmpty(item.summary) case final summary?) ...[
                        const SizedBox(height: 6),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, height: 1.25),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.originalAirDate case final originalAirDate?) ...[
                        const SizedBox(height: 4),
                        Text(
                          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(originalAirDate),
                          style: theme.textTheme.labelSmall?.copyWith(color: tk.textMuted),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  MediaServerClient? _clientFor(BuildContext context, LiveTvProgram? item) {
    final serverId = serverIdOrNull(item?.serverId);
    return serverId == null ? null : context.read<MultiServerProvider>().getClientForServer(serverId);
  }

  String _airingStatusLabel(LiveTvAiringStatus status) => switch (status) {
    LiveTvAiringStatus.newEpisode => 'NEW',
    LiveTvAiringStatus.rerun => 'RERUN',
    LiveTvAiringStatus.premiere => 'PREMIERE',
    LiveTvAiringStatus.unknown => '',
  };
}

class _GuideBackdropPainter extends CustomPainter {
  final Color color;
  final Rect? hole;

  const _GuideBackdropPainter({required this.color, required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (hole case final rect?) {
      path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GuideBackdropPainter oldDelegate) => oldDelegate.color != color || oldDelegate.hole != hole;
}
