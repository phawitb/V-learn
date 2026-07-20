import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/course.dart';
import '../../models/episode.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

const _speeds = [1.0, 1.25, 1.5];

class VideoPlayerScreen extends StatefulWidget {
  final Course course;
  final String initialEpisodeId;

  const VideoPlayerScreen({super.key, required this.course, required this.initialEpisodeId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller;
  late Episode _episode;
  late final Set<String> _completedOverride;
  Timer? _ticker;

  double _currentSeconds = 0;
  double _totalSeconds = 0;
  bool _isPlaying = false;
  int _speedIndex = 0;

  @override
  void initState() {
    super.initState();
    _episode = widget.course.allEpisodes.firstWhere((e) => e.id == widget.initialEpisodeId);
    _completedOverride = widget.course.allEpisodes.where((e) => e.completed).map((e) => e.id).toSet();

    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        playsInline: true,
        strictRelatedVideos: true,
      ),
    );

    _controller.cueVideoById(videoId: _episode.youtubeId, startSeconds: _episode.positionSeconds.toDouble());

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    final playerState = await _controller.playerState;
    final current = await _controller.currentTime;
    final duration = await _controller.duration;
    if (!mounted) return;
    setState(() {
      _isPlaying = playerState == PlayerState.playing;
      _currentSeconds = current;
      if (duration > 0) _totalSeconds = duration;
    });
    if (current > 0) {
      state.setEpisodePosition(_episode.id, current.round());
    }
    if (playerState == PlayerState.ended && _completedOverride.add(_episode.id)) {
      state.markEpisodeCompleted(_episode.id);
      setState(() {});
    }
  }

  void _switchEpisode(Episode episode) {
    setState(() {
      _episode = episode;
      _currentSeconds = 0;
      _totalSeconds = 0;
    });
    _controller.loadVideoById(videoId: episode.youtubeId, startSeconds: episode.positionSeconds.toDouble());
  }

  void _togglePlay() {
    if (_isPlaying) {
      _controller.pauseVideo();
    } else {
      _controller.playVideo();
    }
  }

  void _skip(int deltaSeconds) {
    final target = (_currentSeconds + deltaSeconds).clamp(0, _totalSeconds == 0 ? 1e9 : _totalSeconds);
    _controller.seekTo(seconds: target.toDouble(), allowSeekAhead: true);
  }

  void _cycleSpeed() {
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    _controller.setPlaybackRate(_speeds[_speedIndex]);
  }

  String _fmt(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(episodeTitle: _episode.title, courseCode: course.code, instructor: course.instructor),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(controller: _controller),
            ),
            _ControlsBar(
              current: _currentSeconds,
              total: _totalSeconds,
              isPlaying: _isPlaying,
              speedLabel: '${_speeds[_speedIndex] == _speeds[_speedIndex].roundToDouble() ? _speeds[_speedIndex].toStringAsFixed(0) : _speeds[_speedIndex]}x',
              fmt: _fmt,
              onScrub: (v) => _controller.seekTo(seconds: v, allowSeekAhead: true),
              onTogglePlay: _togglePlay,
              onSkipBack: () => _skip(-10),
              onSkipForward: () => _skip(10),
              onCycleSpeed: _cycleSpeed,
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                ),
                child: _EpisodeList(
                  course: course,
                  currentEpisode: _episode,
                  completedIds: _completedOverride,
                  onSelect: _switchEpisode,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String episodeTitle;
  final String courseCode;
  final String instructor;

  const _TopBar({required this.episodeTitle, required this.courseCode, required this.instructor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                episodeTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(courseCode),
                content: Text('ผู้สอน: $instructor'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  final double current;
  final double total;
  final bool isPlaying;
  final String speedLabel;
  final String Function(double) fmt;
  final ValueChanged<double> onScrub;
  final VoidCallback onTogglePlay;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onCycleSpeed;

  const _ControlsBar({
    required this.current,
    required this.total,
    required this.isPlaying,
    required this.speedLabel,
    required this.fmt,
    required this.onScrub,
    required this.onTogglePlay,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onCycleSpeed,
  });

  @override
  Widget build(BuildContext context) {
    final max = total > 0 ? total : 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: current.clamp(0, max),
              max: max,
              onChanged: onScrub,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmt(current), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: onSkipBack),
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 34),
                    onPressed: onTogglePlay,
                  ),
                  IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: onSkipForward),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: onCycleSpeed,
                    child: Text(speedLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpisodeList extends StatelessWidget {
  final Course course;
  final Episode currentEpisode;
  final Set<String> completedIds;
  final ValueChanged<Episode> onSelect;

  const _EpisodeList({
    required this.course,
    required this.currentEpisode,
    required this.completedIds,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Row(
          children: const [
            Icon(Icons.expand_more, color: AppColors.inkFaint),
            SizedBox(width: 4),
            Text('เลือกตอน', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 12),
        for (final chapter in course.chapters) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(chapter.title, style: const TextStyle(color: AppColors.inkFaint, fontSize: 12.5)),
          ),
          for (final episode in chapter.episodes) _episodeTile(context, episode),
        ],
      ],
    );
  }

  Widget _episodeTile(BuildContext context, Episode episode) {
    final isActive = episode.id == currentEpisode.id;
    final isDone = completedIds.contains(episode.id);
    return InkWell(
      onTap: () => onSelect(episode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.blueDark : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.play_circle_fill : (isDone ? Icons.check_circle : Icons.play_circle_outline),
              size: 18,
              color: isActive ? Colors.white : (isDone ? AppColors.green : AppColors.inkFaint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                episode.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? Colors.white : AppColors.ink,
                ),
              ),
            ),
            Text(
              episode.durationLabel,
              style: TextStyle(fontSize: 11.5, color: isActive ? Colors.white70 : AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
