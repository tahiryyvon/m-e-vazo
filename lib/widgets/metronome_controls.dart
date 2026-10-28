import 'package:flutter/material.dart';
import '../services/metronome.dart';

const _amber = Color(0xFFFF8C00);

/// Compact metronome control for the player bar: on/off button with a beat
/// pulse, and the tempo, which opens the settings sheet.
class MetronomeControls extends StatelessWidget {
  final Metronome metronome;
  const MetronomeControls({super.key, required this.metronome});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: metronome,
      builder: (context, _) {
        final on = metronome.enabled;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: on ? 'Désactiver le métronome (T)' : 'Activer le métronome (T)',
              onPressed: metronome.toggle,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.av_timer_rounded, color: on ? _amber : Colors.white54),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showMetronomeSheet(context, metronome),
              child: Tooltip(
                message: 'Réglages du métronome',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BeatPulse(metronome: metronome),
                      const SizedBox(width: 4),
                      Text(
                        '${metronome.bpm.round()}',
                        style: TextStyle(
                          color: on ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Dot that flashes on each beat, bigger on the first beat of the bar.
class _BeatPulse extends StatelessWidget {
  final Metronome metronome;
  const _BeatPulse({required this.metronome});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: metronome.beat,
      builder: (context, beat, _) {
        final active = metronome.enabled && beat >= 0;
        final accent = active && metronome.grid.isAccent(beat);
        return TweenAnimationBuilder<double>(
          key: ValueKey(beat),
          tween: Tween(begin: active ? 1 : 0, end: 0),
          duration: const Duration(milliseconds: 220),
          builder: (context, flash, _) => Container(
            width: accent ? 10 : 8,
            height: accent ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(Colors.white24, accent ? Colors.redAccent : _amber, flash),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showMetronomeSheet(BuildContext context, Metronome metronome) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF161616),
    showDragHandle: true,
    builder: (context) => AnimatedBuilder(
      animation: metronome,
      builder: (context, _) {
        final detected = metronome.detectedBpm;
        Widget step(String label, VoidCallback onTap, String tooltip) => Tooltip(
              message: tooltip,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: Text(label),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _amber,
                  title: const Text('Métronome', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    detected == null
                        ? 'Tempo non détecté pour ce morceau : réglage manuel.'
                        : 'Calé sur les temps détectés du morceau (${detected.toStringAsFixed(0)} BPM).',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: metronome.enabled,
                  onChanged: metronome.setEnabled,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    step('÷2', metronome.halve, 'Moitié du tempo'),
                    step('−1', () => metronome.nudge(-1), 'Ralentir de 1 BPM'),
                    SizedBox(
                      width: 92,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${metronome.bpm.round()}',
                              style: const TextStyle(color: _amber, fontSize: 30, fontWeight: FontWeight.w800)),
                          Text(metronome.isManual && detected != null ? 'BPM (manuel)' : 'BPM',
                              style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    step('+1', () => metronome.nudge(1), 'Accélérer de 1 BPM'),
                    step('×2', metronome.doubleTempo, 'Double du tempo'),
                  ],
                ),
                if (detected != null && metronome.isManual)
                  TextButton(
                    onPressed: metronome.resetToDetected,
                    child: const Text('Revenir au tempo détecté'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.av_timer_rounded, color: Colors.white54, size: 20),
                    Expanded(
                      child: Slider(
                        value: metronome.volume,
                        activeColor: _amber,
                        label: '${(metronome.volume * 100).round()} %',
                        semanticFormatterCallback: (v) => 'Volume du métronome : ${(v * 100).round()} %',
                        onChanged: metronome.setVolume,
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(metronome.volume * 100).round()} %',
                          textAlign: TextAlign.end,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
                const Text(
                  'Astuce : coupe la chanson avec le haut-parleur. Le métronome continue, '
                  'les paroles et les accords défilent toujours.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
