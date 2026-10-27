import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SoftPlayerScreen(),
    );
  }
}

class SoftPlayerScreen extends StatefulWidget {
  const SoftPlayerScreen({super.key});

  @override
  State<SoftPlayerScreen> createState() => _SoftPlayerScreenState();
}

class _SoftPlayerScreenState extends State<SoftPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player;

  // AnimationController synced to display refresh rate (VSync 60/120Hz)
  late final AnimationController _fadeController;
  late final CurvedAnimation _curvedAnimation;
  VoidCallback? _fadeOnComplete;

  double _fadeStartVolume = 0.0;
  double _fadeTargetVolume = 0.0;
  double _currentVolume = 0.0;
  double _userVolume = 100.0;
  String? _selectedFileName;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isSeeking = false;
  Duration _seekPosition = Duration.zero;

  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;

  static const int _fadeDurationMs = 500;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _player.setVolume(0.0);

    // VSync-driven AnimationController: completely eliminates Timer.periodic jitter
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _fadeDurationMs),
    );

    // Curves.easeInOutCubic applies a smooth S-curve to counteract the logarithmic
    // human perception of loudness, preventing abrupt volume jumps near 0.
    _curvedAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOutCubic,
    );

    _curvedAnimation.addListener(() {
      final double progress = _curvedAnimation.value;
      final double newVolume =
          _fadeStartVolume + (_fadeTargetVolume - _fadeStartVolume) * progress;
      _currentVolume = newVolume;
      _player.setVolume(newVolume);

      if (mounted) {
        setState(() {});
      }
    });

    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _fadeOnComplete?.call();
        _fadeOnComplete = null;
      }
    });

    // Listen to playback position stream
    _positionSubscription = _player.stream.position.listen((pos) {
      if (!_isSeeking && mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });

    // Listen to total duration stream
    _durationSubscription = _player.stream.duration.listen((dur) {
      if (mounted) {
        setState(() {
          _totalDuration = dur;
        });
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _curvedAnimation.dispose();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Smoothly transitions volume towards [targetVolume] using VSync animation.
  /// Handles interruptions seamlessly without volume jumps.
  void _startFade({
    required double targetVolume,
    VoidCallback? onComplete,
  }) {
    // 1. Immediately halt any in-flight fade animation
    _fadeController.stop();
    _fadeOnComplete = null;

    final double startVolume = _currentVolume;
    final double volumeDelta = (targetVolume - startVolume).abs();

    if (volumeDelta < 0.001) {
      _currentVolume = targetVolume;
      _player.setVolume(targetVolume);
      if (mounted) setState(() {});
      onComplete?.call();
      return;
    }

    // Scale duration proportionally to distance to maintain consistent slew rate
    final double maxRange = _userVolume > 0 ? _userVolume : 100.0;
    final int effectiveDurationMs =
        (_fadeDurationMs * (volumeDelta / maxRange)).round();

    if (effectiveDurationMs <= 0) {
      _currentVolume = targetVolume;
      _player.setVolume(targetVolume);
      if (mounted) setState(() {});
      onComplete?.call();
      return;
    }

    _fadeStartVolume = startVolume;
    _fadeTargetVolume = targetVolume;
    _fadeOnComplete = onComplete;
    _fadeController.duration = Duration(milliseconds: effectiveDurationMs);

    // Forward from 0.0 to 1.0 driven by display VSync
    _fadeController.forward(from: 0.0);
  }

  /// Soft Play: Fades volume in to [_userVolume] over 500ms along the S-curve.
  Future<void> _softPlay() async {
    if (_player.state.playlist.medias.isEmpty) return;

    final double target = _userVolume > 0 ? _userVolume : 100.0;

    if (_player.state.playing &&
        _currentVolume >= target &&
        !_fadeController.isAnimating) {
      return;
    }

    if (!_player.state.playing) {
      _currentVolume = 0.0;
      await _player.setVolume(0.0);
      await _player.play();
    } else {
      await _player.play();
    }

    _startFade(
      targetVolume: target,
      onComplete: null,
    );
  }

  /// Soft Pause: Incrementally lowers volume down to 0 over 500ms along the S-curve.
  /// Pauses playback only once volume reaches 0.
  void _softPause() {
    if (_player.state.playlist.medias.isEmpty) return;
    if (!_player.state.playing && _currentVolume <= 0.0) return;

    _startFade(
      targetVolume: 0.0,
      onComplete: () {
        _player.pause();
      },
    );
  }

  /// Picks a local audio file (.flac, .mp3, etc.) and loads it into media_kit.
  Future<void> _pickAudioFile() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a', 'opus'],
      );

      if (pickedFiles.isNotEmpty && pickedFiles.first.path != null) {
        final file = pickedFiles.first;

        _fadeController.stop();
        _fadeOnComplete = null;
        _currentVolume = 0.0;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;

        await _player.setVolume(0.0);
        await _player.open(Media(file.path!), play: false);

        setState(() {
          _selectedFileName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking audio file: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMedia = _player.state.playlist.medias.isNotEmpty;
    final double maxDurationMs =
        max(1.0, _totalDuration.inMilliseconds.toDouble());
    final double currentPositionMs =
        (_isSeeking ? _seekPosition : _currentPosition)
            .inMilliseconds
            .toDouble()
            .clamp(0.0, maxDurationMs);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Selected file name
                Text(
                  _selectedFileName ?? 'No file selected',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),

                // Pick Audio File button
                ElevatedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pick Audio File'),
                ),
                const SizedBox(height: 24),

                // Audio Seek Bar / Progress Bar
                Row(
                  children: [
                    Text(
                      _formatDuration(
                        _isSeeking ? _seekPosition : _currentPosition,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: currentPositionMs,
                        min: 0.0,
                        max: maxDurationMs,
                        onChanged: hasMedia
                            ? (value) {
                                setState(() {
                                  _isSeeking = true;
                                  _seekPosition =
                                      Duration(milliseconds: value.toInt());
                                });
                              }
                            : null,
                        onChangeEnd: hasMedia
                            ? (value) async {
                                final target =
                                    Duration(milliseconds: value.toInt());
                                await _player.seek(target);
                                setState(() {
                                  _currentPosition = target;
                                  _isSeeking = false;
                                });
                              }
                            : null,
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDuration),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Soft Play and Soft Pause buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: hasMedia ? _softPlay : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Soft Play'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: hasMedia ? _softPause : null,
                      icon: const Icon(Icons.pause),
                      label: const Text('Soft Pause'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Volume Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _currentVolume <= 0
                            ? Icons.volume_off
                            : _currentVolume < 50
                                ? Icons.volume_down
                                : Icons.volume_up,
                      ),
                      tooltip: _currentVolume > 0 ? 'Mute' : 'Unmute',
                      onPressed: () {
                        _fadeController.stop();
                        _fadeOnComplete = null;
                        if (_currentVolume > 0) {
                          setState(() {
                            _currentVolume = 0.0;
                          });
                          _player.setVolume(0.0);
                        } else {
                          final restoreVol =
                              _userVolume > 0 ? _userVolume : 100.0;
                          setState(() {
                            _currentVolume = restoreVol;
                          });
                          _player.setVolume(restoreVol);
                        }
                      },
                    ),
                    SizedBox(
                      width: 220,
                      child: Slider(
                        value: _currentVolume.clamp(0.0, 100.0),
                        min: 0.0,
                        max: 100.0,
                        divisions: 100,
                        label: '${_currentVolume.round()}%',
                        onChanged: (value) {
                          _fadeController.stop();
                          _fadeOnComplete = null;
                          setState(() {
                            _currentVolume = value;
                            if (value > 0) {
                              _userVolume = value;
                            }
                          });
                          _player.setVolume(value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${_currentVolume.round()}%',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}