# 🎵 Logarithmic Soft Pause & Play (Flutter / Harmonoid Engine)

A lightweight, sandboxed Flutter desktop audio application designed to evaluate and demonstrate smooth, pop-free **"Soft Play"** and **"Soft Pause"** audio transitions for music players like Harmonoid.

Built on top of [`media_kit`](https://pub.dev/packages/media_kit) (`libmpv`) and Flutter's display-synchronized `AnimationController`, this project completely eliminates audio pops, zipper noise, and event-loop stutter during volume transitions.

---

## ⚡ The Problem with Traditional Audio Fading

Most naive audio fading implementations suffer from two critical audio engineering flaws:

1. **Human Hearing is Logarithmic, Not Linear**:
   Human perception of loudness follows the Weber-Fechner law ($\Delta L \propto \Delta V / V$). Stepping linear volume uniformly ($10, 20, 30\dots$) creates a massive perceived jump from $0 \to 10\%$ ($-\infty \text{ dB}$ to $-20 \text{ dB}$), while $90 \to 100\%$ is barely noticeable.
2. **`Timer.periodic` Stutters**:
   Standard timers run on Dart's single-threaded event loop and are subject to thread scheduling jitter. When the UI is busy, timer ticks execute at uneven intervals, creating audible stepping artifacts ("zipper noise").

---

## 🛠️ The Solution

- **Hardware VSync Synchronization (60Hz / 120Hz / 144Hz)**:
  Replaces `Timer.periodic` with Flutter's `AnimationController` (`SingleTickerProviderStateMixin`). Volume updates are delivered precisely on each display frame refresh, guaranteeing butter-smooth transitions.
- **Psychoacoustic S-Curve (`Curves.easeInOutCubic`)**:
  Applies an S-curve that slows down gain changes near silence ($t \approx 0$). At 10% elapsed time, volume is only at $\approx 1.6\%$ instead of $10\%$, preventing sudden loudness bursts.
- **Glitch-Free Interruption Handling**:
  If a user hits **Soft Play** while the track is still fading out (e.g. at 35% volume), the player **does not** abruptly cut to 0. It halts the fade-out, calculates the proportional remaining time, and smoothly ramps upward to the target volume.
- **True Soft Pause**:
  `player.pause()` is only executed once the gain envelope reaches exactly `0.0`.

---

## ✨ Features

- **Soft Play & Soft Pause**: 500ms S-curved volume fades with zero zipper noise.
- **Interruption-Safe Logic**: Rapidly clicking play/pause dynamically reverses direction without erratic jumps.
- **Audio Seek & Scrub Bar**: Real-time position tracking (`mm:ss / mm:ss`) with drag-to-seek support.
- **Interactive Volume Controls**: Slider and mute toggle with live 60fps visual synchronization during automated fades.
- **Wide Format Support**: Plays `.mp3`, `.flac`, `.wav`, `.aac`, `.ogg`, `.m4a`, and `.opus`.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.13+)
- Windows desktop build tools (Visual Studio C++ build tools)

### Installation & Run

```bash
# 1. Clone the repository
git clone https://github.com/Combiler01/Logarithmic-Soft-Pause-Play-Flutter-for-Harmonoid.git
cd Logarithmic-Soft-Pause-Play-Flutter-for-Harmonoid

# 2. Install dependencies
flutter pub get

# 3. Run on Windows desktop
flutter run -d windows
```

---

## 🧪 Testing

The repository includes pure unit tests verifying the cubic curve mathematics and interruption handling:

```bash
flutter test
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
