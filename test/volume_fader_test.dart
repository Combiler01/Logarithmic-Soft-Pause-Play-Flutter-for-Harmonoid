import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

class CurvedFaderHarness {
  final TickerProvider vsync;
  late final AnimationController controller;
  late final CurvedAnimation curvedAnimation;
  void Function()? onComplete;

  double currentVolume = 0.0;
  double userVolume = 100.0;
  double startVolume = 0.0;
  double targetVolume = 0.0;
  bool isPlaying = false;
  int pauseCount = 0;
  int playCount = 0;

  CurvedFaderHarness(this.vsync) {
    controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
    );
    curvedAnimation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    curvedAnimation.addListener(() {
      final progress = curvedAnimation.value;
      currentVolume = startVolume + (targetVolume - startVolume) * progress;
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        onComplete?.call();
        onComplete = null;
      }
    });
  }

  void startFade({
    required double target,
    void Function()? onDone,
  }) {
    controller.stop();
    onComplete = null;
    startVolume = currentVolume;
    targetVolume = target;
    onComplete = onDone;

    final delta = (target - startVolume).abs();
    final effectiveDuration = (500 * (delta / 100.0)).round();
    if (effectiveDuration <= 0) {
      currentVolume = target;
      onDone?.call();
      return;
    }

    controller.duration = Duration(milliseconds: effectiveDuration);
    controller.forward(from: 0.0);
  }

  void softPlay() {
    if (!isPlaying) {
      currentVolume = 0.0;
      isPlaying = true;
      playCount++;
    }
    startFade(target: userVolume);
  }

  void softPause() {
    startFade(
      target: 0.0,
      onDone: () {
        isPlaying = false;
        pauseCount++;
      },
    );
  }

  void dispose() {
    curvedAnimation.dispose();
    controller.dispose();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Curved AnimationController Volume Fader Tests', () {
    test('Soft Play eases volume from 0 to 100 along S-curve', () {
      final vsync = const TestVSync();
      final fader = CurvedFaderHarness(vsync);

      expect(fader.currentVolume, 0.0);
      expect(fader.isPlaying, false);

      fader.softPlay();
      expect(fader.isPlaying, true);

      // Advance by 10% of time (50ms)
      fader.controller.value = 0.1;
      // Linear volume would be 10.0%, but with easeInOutCubic it is ~1.6%.
      // This confirms the low-end volume rises very gradually, preventing the 0 -> 10 jump!
      expect(fader.currentVolume, closeTo(1.6, 0.5));

      // Advance to halfway (250ms)
      fader.controller.value = 0.5;
      expect(fader.currentVolume, closeTo(50.0, 3.0));

      // Complete the animation
      fader.controller.value = 1.0;
      expect(fader.currentVolume, closeTo(100.0, 0.1));

      fader.dispose();
    });

    test('Soft Pause eases volume down to 0 and pauses only on completion', () {
      final vsync = const TestVSync();
      final fader = CurvedFaderHarness(vsync);
      fader.currentVolume = 100.0;
      fader.isPlaying = true;

      fader.softPause();
      expect(fader.isPlaying, true); // Still playing!

      // At 50%
      fader.controller.value = 0.5;
      expect(fader.currentVolume, closeTo(50.0, 3.0));
      expect(fader.isPlaying, true);

      // At completion (value = 1.0)
      fader.controller.value = 1.0;
      // Trigger status listener callback
      fader.onComplete?.call();
      expect(fader.currentVolume, closeTo(0.0, 0.1));
      expect(fader.isPlaying, false); // Paused!
      expect(fader.pauseCount, 1);

      fader.dispose();
    });

    test('Interruption: Soft Play during Soft Pause reverses smoothly without jumping to 0', () {
      final vsync = const TestVSync();
      final fader = CurvedFaderHarness(vsync);
      fader.currentVolume = 100.0;
      fader.isPlaying = true;

      // Start fade out
      fader.softPause();
      fader.controller.value = 0.6; // Mid-way down
      final currentVol = fader.currentVolume;
      expect(currentVol, closeTo(24.5, 0.5));

      // User hits Soft Play mid-way
      fader.softPlay();

      // Volume must NOT jump to 0.0; it should start from current volume (~24.5)
      expect(fader.currentVolume, closeTo(currentVol, 0.1));
      expect(fader.isPlaying, true);
      // Pause callback should not have been called
      expect(fader.pauseCount, 0);

      fader.dispose();
    });
  });
}
