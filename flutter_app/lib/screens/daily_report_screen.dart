import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../state/active_user.dart';

class DailyReportScreen extends StatelessWidget {
  const DailyReportScreen({super.key});

  static const Map<int, String> postureNames = {
    1: 'Posture 1',
    2: 'Posture 2',
    3: 'Posture 3',
    4: 'Posture 4',
    5: 'Posture 5',
    6: 'Posture 6',
  };

  String _todayKeyUtc() {
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<ActiveUser>().userId;
    final todayKey = _todayKeyUtc();
    final path = 'users/$userId/history/$todayKey';
    final ref = FirebaseDatabase.instance.ref(path);

    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final value = snapshot.data!.snapshot.value;

        if (value == null) {
          return _DailyScaffold(
            headerSubtitle: "User: $userId • UTC day: $todayKey",
            child: _EmptyCard(
              title: 'No daily data yet',
              message:
                  'No history events found for today.\n\nWaiting for chair writes under:\n$path',
            ),
          );
        }

        // expected: Map(pushId -> {prediction, ts, ...})
        final events = <Map<String, dynamic>>[];
        if (value is Map) {
          for (final entry in value.entries) {
            final v = entry.value;
            if (v is Map) {
              final predictionRaw = v['prediction'];
              final tsRaw = v['ts'];
              if (predictionRaw == null) continue;

              final prediction = (predictionRaw as num).toInt();
              final ts = tsRaw is num ? tsRaw.toInt() : null;
              events.add({'prediction': prediction, 'ts': ts});
            }
          }
        }

        // If map exists but no valid events
        if (events.isEmpty) {
          return _DailyScaffold(
            headerSubtitle: "User: $userId • UTC day: $todayKey",
            child: _EmptyCard(
              title: 'No daily events yet',
              message:
                  'The day node exists but no prediction events were found.\nSend a prediction from the chair.',
            ),
          );
        }

        final counts = <int, int>{};
        final tsList = <int>[];

        for (final e in events) {
          final p = e['prediction'] as int;
          counts[p] = (counts[p] ?? 0) + 1;

          final ts = e['ts'] as int?;
          if (ts != null) tsList.add(ts);
        }

        tsList.sort();
        Duration estimatedDuration = Duration.zero;
        if (tsList.length >= 2) {
          estimatedDuration = Duration(seconds: tsList.last - tsList.first);
        }

        int? mostCommon;
        int mostCommonCount = 0;
        counts.forEach((p, c) {
          if (c > mostCommonCount) {
            mostCommonCount = c;
            mostCommon = p;
          }
        });

        final sessions = events.length;
        final maxCount = counts.isEmpty ? 1 : counts.values.reduce(max);

        return _DailyScaffold(
          headerSubtitle: "User: $userId • UTC day: $todayKey",
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Posture distribution (today)",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        ...postureNames.entries.map((entry) {
                          final p = entry.key;
                          final name = entry.value;
                          final c = counts[p] ?? 0;
                          final ratio = c / maxCount;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(name)),
                                    Text('$c', style: TextStyle(color: Colors.grey.shade700)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: LinearProgressIndicator(
                                    value: ratio.clamp(0.0, 1.0),
                                    minHeight: 10,
                                    backgroundColor: Colors.grey.shade200,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.access_time, color: Colors.blue.shade700, size: 32),
                    title: const Text("Estimated sitting time"),
                    subtitle: Text(_formatDuration(estimatedDuration)),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.chair_alt, color: Colors.blue.shade700, size: 32),
                    title: const Text("Most common posture"),
                    subtitle: Text(
                      mostCommon == null
                          ? "N/A"
                          : "${postureNames[mostCommon] ?? 'Posture $mostCommon'} ($mostCommonCount samples)",
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.auto_graph, color: Colors.blue.shade700, size: 32),
                    title: const Text("Number of samples"),
                    subtitle: Text("$sessions today"),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration d) {
    if (d == Duration.zero) return "0h 00m";
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return "${hours}h ${minutes.toString().padLeft(2, '0')}m";
  }
}

class _DailyScaffold extends StatelessWidget {
  final String headerSubtitle;
  final Widget child;

  const _DailyScaffold({required this.headerSubtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
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
                const Icon(Icons.calendar_today, size: 60, color: Colors.white),
                const SizedBox(height: 10),
                const Text(
                  "Daily Report",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headerSubtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey.shade600),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}
