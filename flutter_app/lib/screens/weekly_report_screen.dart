import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../state/active_user.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  DatabaseReference? _historyRef;

  bool _loading = true;
  String? _error;

  String _currentUserId = '';

  // Week data
  List<_DayBucket> _thisWeek = [];
  List<_DayBucket> _lastWeek = [];

  // Aggregates
  Map<int, int> _thisWeekCounts = {};
  int _thisWeekTotalSamples = 0;

  Map<int, int> _lastWeekCounts = {};
  int _lastWeekTotalSamples = 0;

  // Labels (optional)
  static const Map<int, String> postureNames = {
    1: 'Posture 1',
    2: 'Posture 2',
    3: 'Posture 3',
    4: 'Posture 4',
    5: 'Posture 5',
    6: 'Posture 6',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final userId = context.watch<ActiveUser>().userId;

    // Run only when user changes
    if (userId != _currentUserId) {
      _currentUserId = userId;
      _historyRef = FirebaseDatabase.instance.ref('users/$_currentUserId/history');
      _load();
    }
  }

  DateTime _startOfWeekUtc(DateTime utcNow) {
    // Monday-start week
    final dow = utcNow.weekday; // Mon=1..Sun=7
    return DateTime.utc(utcNow.year, utcNow.month, utcNow.day)
        .subtract(Duration(days: dow - 1));
  }

  String _dateKeyUtc(DateTime utcDay) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utcDay.year}-${two(utcDay.month)}-${two(utcDay.day)}';
  }

  String _shortDay(DateTime utcDay) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[utcDay.weekday - 1];
  }

  Future<int> _countSamplesForDateKey(String dateKey) async {
    final ref = _historyRef;
    if (ref == null) return 0;

    final snap = await ref.child(dateKey).get();
    final v = snap.value;
    if (v is Map) return v.length;
    return 0;
  }

  Future<Map<int, int>> _countPosturesForDateKey(String dateKey) async {
    final ref = _historyRef;
    if (ref == null) return {};

    final snap = await ref.child(dateKey).get();
    final v = snap.value;

    final counts = <int, int>{};
    if (v is Map) {
      for (final entry in v.entries) {
        final event = entry.value;
        if (event is Map && event['prediction'] != null) {
          final p = (event['prediction'] as num).toInt();
          counts[p] = (counts[p] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  void _mergeCounts(Map<int, int> into, Map<int, int> add) {
    add.forEach((k, v) {
      into[k] = (into[k] ?? 0) + v;
    });
  }

  int? _mostCommonPosture(Map<int, int> counts) {
    int? best;
    int bestCount = 0;
    counts.forEach((p, c) {
      if (c > bestCount) {
        bestCount = c;
        best = p;
      }
    });
    return best;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _thisWeek = [];
      _lastWeek = [];
      _thisWeekCounts = {};
      _lastWeekCounts = {};
      _thisWeekTotalSamples = 0;
      _lastWeekTotalSamples = 0;
    });

    try {
      final nowUtc = DateTime.now().toUtc();
      final startThisWeek = _startOfWeekUtc(nowUtc);
      final startLastWeek = startThisWeek.subtract(const Duration(days: 7));

      final thisWeekDays = List.generate(7, (i) => startThisWeek.add(Duration(days: i)));
      final lastWeekDays = List.generate(7, (i) => startLastWeek.add(Duration(days: i)));

      final thisWeekBuckets = <_DayBucket>[];
      final lastWeekBuckets = <_DayBucket>[];

      final thisWeekCounts = <int, int>{};
      final lastWeekCounts = <int, int>{};

      int thisWeekTotal = 0;
      int lastWeekTotal = 0;

      for (final day in thisWeekDays) {
        final key = _dateKeyUtc(day);
        final dayCount = await _countSamplesForDateKey(key);
        thisWeekTotal += dayCount;

        thisWeekBuckets.add(_DayBucket(dayUtc: day, dateKey: key, totalSamples: dayCount));

        final dayPostures = await _countPosturesForDateKey(key);
        _mergeCounts(thisWeekCounts, dayPostures);
      }

      for (final day in lastWeekDays) {
        final key = _dateKeyUtc(day);
        final dayCount = await _countSamplesForDateKey(key);
        lastWeekTotal += dayCount;

        lastWeekBuckets.add(_DayBucket(dayUtc: day, dateKey: key, totalSamples: dayCount));

        final dayPostures = await _countPosturesForDateKey(key);
        _mergeCounts(lastWeekCounts, dayPostures);
      }

      if (!mounted) return;

      setState(() {
        _thisWeek = thisWeekBuckets;
        _lastWeek = lastWeekBuckets;

        _thisWeekCounts = thisWeekCounts;
        _lastWeekCounts = lastWeekCounts;

        _thisWeekTotalSamples = thisWeekTotal;
        _lastWeekTotalSamples = lastWeekTotal;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _buildTrendText({required int thisWeekTotal, required int lastWeekTotal}) {
    if (thisWeekTotal == 0 && lastWeekTotal == 0) return "No data yet.";
    if (lastWeekTotal == 0) return "Up from last week (no last-week data).";

    final diff = thisWeekTotal - lastWeekTotal;
    final pct = (diff / lastWeekTotal) * 100;

    if (diff == 0) return "Same as last week (0%).";
    final direction = diff > 0 ? "Up" : "Down";
    final sign = diff > 0 ? "+" : "";
    return "$direction vs last week: $sign$diff samples (${pct.toStringAsFixed(1)}%).";
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Error: $_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final mostCommonThisWeek = _mostCommonPosture(_thisWeekCounts);
    final mostCommonLabel = mostCommonThisWeek == null
        ? 'N/A'
        : '${postureNames[mostCommonThisWeek] ?? 'Posture $mostCommonThisWeek'} '
            '(${_thisWeekCounts[mostCommonThisWeek]} samples)';

    final trendText = _buildTrendText(
      thisWeekTotal: _thisWeekTotalSamples,
      lastWeekTotal: _lastWeekTotalSamples,
    );

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.bar_chart, size: 60, color: Colors.white),
                const SizedBox(height: 10),
                const Text(
                  "Weekly Report",
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  "User: $_currentUserId (UTC)",
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Chart card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Samples per day (this week)",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    _WeeklyBars(days: _thisWeek, labelForDay: _shortDay),
                    const SizedBox(height: 10),
                    Text(
                      "Total this week: $_thisWeekTotalSamples",
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (_thisWeekTotalSamples == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "No weekly data for this user yet.",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Insights
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.person, color: Colors.blue.shade700, size: 32),
                title: const Text("Most common posture this week"),
                subtitle: Text(mostCommonLabel),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.trending_up, color: Colors.blue.shade700, size: 32),
                title: const Text("Trend vs last week"),
                subtitle: Text(trendText),
              ),
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _DayBucket {
  final DateTime dayUtc;
  final String dateKey;
  final int totalSamples;

  _DayBucket({
    required this.dayUtc,
    required this.dateKey,
    required this.totalSamples,
  });
}

class _WeeklyBars extends StatelessWidget {
  final List<_DayBucket> days;
  final String Function(DateTime dayUtc) labelForDay;

  const _WeeklyBars({
    required this.days,
    required this.labelForDay,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = days.isEmpty ? 1 : max(1, days.map((d) => d.totalSamples).reduce(max));

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((d) {
          final ratio = d.totalSamples / maxVal;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${d.totalSamples}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: ratio.clamp(0.0, 1.0),
                        widthFactor: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade400,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(labelForDay(d.dayUtc), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
