/// Removes short, ambiguous A-B-A excursions after timing refinement.
/// Strong short changes and transitions to a different following chord survive.
class ChordTimelineFilter {
  static List<(double, String)> stabilize(
    List<(double, String)> segments,
    List<double> times,
    List<Map<String, double>?> scores,
  ) {
    final output = <(double, String)>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (output.isNotEmpty && i + 1 < segments.length &&
          output.last.$2 == segments[i + 1].$2 &&
          segments[i + 1].$1 - segment.$1 <= 0.8) {
        var advantage = 0.0;
        var count = 0;
        for (var frame = 0; frame < times.length; frame++) {
          if (times[frame] < segment.$1) continue;
          if (times[frame] >= segments[i + 1].$1) break;
          final score = scores[frame];
          if (score == null) continue;
          advantage += (score[segment.$2] ?? 0) - (score[output.last.$2] ?? 0);
          count++;
        }
        if (count > 0 && advantage / count < 0.06) continue;
      }
      if (output.isEmpty || output.last.$2 != segment.$2) output.add(segment);
    }
    return output;
  }
}
