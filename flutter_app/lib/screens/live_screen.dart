import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../state/active_user.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  // --- CONFIG ---
  static const int maxSittingMinutes = 60;
  static const int signalTimeoutSeconds = 15; 

  // --- UI STATE ---
  String _connectionStatus = "Connecting..."; 
  Color _statusColor = Colors.grey;
  int _currentPosture = -1;
  String _debugTime = "--:--";
  DateTime? _lastSignalTime;

  // --- SUBSCRIPTIONS ---
  StreamSubscription? _dataSubscription;
  Timer? _logicTimer;

  @override
  void initState() {
    super.initState();
    // This loop runs every second to check if chair is still ON 
    // and to update the timer display on screen.
    _logicTimer = Timer.periodic(const Duration(seconds: 1), (_) => _processLogic());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<ActiveUser>().userId;
    _setupStream(userId);
  }

  void _setupStream(String userId) {
    _dataSubscription?.cancel();
    final path = 'users/$userId/live/posture';
    final ref = FirebaseDatabase.instance.ref(path);

    _dataSubscription = ref.onValue.listen((event) {
      final value = event.snapshot.value;
      if (value == null || value is! Map) return;

      final map = Map<dynamic, dynamic>.from(value);
      final ts = map['ts']; 
      
      if (ts is num) {
        final signalTime = DateTime.fromMillisecondsSinceEpoch(
          ts.toInt() * 1000, 
          isUtc: true
        ).toLocal();

        if (mounted) {
          setState(() {
            _lastSignalTime = signalTime;
            _currentPosture = (map['prediction'] as num?)?.toInt() ?? -1;
            _debugTime = "${signalTime.hour}:${signalTime.minute.toString().padLeft(2, '0')}:${signalTime.second.toString().padLeft(2, '0')}";
          });
        }
      }
    });
  }

  void _processLogic() {
    if (!mounted) return;
    final activeUser = context.read<ActiveUser>();
    final now = DateTime.now();

    // 1. Heartbeat Check (Did the ESP32 send data recently?)
    bool isChairActive = false;
    if (_lastSignalTime != null) {
      final diff = now.difference(_lastSignalTime!).inSeconds;
      if (diff < signalTimeoutSeconds) isChairActive = true;
    }

    if (!isChairActive) {
      // Chair is OFF: Update UI and reset timer in Provider
      if (_connectionStatus != "Chair OFF") {
        setState(() {
          _connectionStatus = "Chair OFF";
          _statusColor = Colors.grey;
        });
      }
      activeUser.updateSession(null, false);
    } else {
      // Chair is ON: Update UI and handle timer
      if (_connectionStatus != "Monitoring") {
        setState(() {
          _connectionStatus = "Monitoring";
          _statusColor = Colors.green;
        });
      }
      _handleSittingLogic(activeUser);
    }

    // 2. IMPORTANT: Trigger a rebuild so the timer text on screen updates every second
    setState(() {}); 
  }

  void _handleSittingLogic(ActiveUser activeUser) {
    final isSitting = (_currentPosture > 0); 

    if (isSitting) {
      if (activeUser.sittingStartTime == null) {
        activeUser.updateSession(DateTime.now(), false);
      }
      
      final durationMinutes = DateTime.now().difference(activeUser.sittingStartTime!).inMinutes;
      
      if (durationMinutes >= maxSittingMinutes && !activeUser.alertShown && !activeUser.isMuted) {
        _showAlert(activeUser);
      }
    } else {
      // User is standing: Reset
      activeUser.updateSession(null, false);
    }
  }

  void _showAlert(ActiveUser activeUser) {
    activeUser.updateSession(activeUser.sittingStartTime, true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⏰ Time to Move!'),
        content: Text('You have been sitting for $maxSittingMinutes minute(s).'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              activeUser.updateSession(DateTime.now(), false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _logicTimer?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeUser = context.watch<ActiveUser>();

    return Scaffold(
      appBar: AppBar(title: const Text('Live Status')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // CONNECTION STATUS BADGE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _statusColor, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: _statusColor),
                  const SizedBox(width: 8),
                  Text(_connectionStatus, style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            Text("Posture Code: $_currentPosture", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text("Signal Received: $_debugTime", style: const TextStyle(color: Colors.grey)),
            
            const SizedBox(height: 40),

            // THE TIMER DISPLAY
            if (activeUser.sittingStartTime != null) ...[
              const Text("CONTINUOUS SITTING TIME", style: TextStyle(letterSpacing: 1.2, fontSize: 12, color: Colors.blueGrey)),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final diff = DateTime.now().difference(activeUser.sittingStartTime!);
                final minutes = diff.inMinutes;
                final seconds = diff.inSeconds % 60;
                return Text(
                  "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                );
              }),
            ] else 
              const Text("Waiting for sitting detection...", style: TextStyle(fontSize: 18, color: Colors.grey, fontStyle: FontStyle.italic)),

            const SizedBox(height: 50),

            // MUTE BUTTON
            SizedBox(
              width: 220,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () => activeUser.setMute(!activeUser.isMuted),
                icon: Icon(activeUser.isMuted ? Icons.notifications_off : Icons.notifications_active),
                label: Text(activeUser.isMuted ? "ALERTS MUTED" : "ALERTS ACTIVE"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: activeUser.isMuted ? Colors.redAccent : Colors.blueAccent,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}