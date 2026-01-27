import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/active_user.dart';
import 'live_screen.dart';
import 'daily_report_screen.dart';
import 'weekly_report_screen.dart';
import 'select_user_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    LiveScreen(),
    DailyReportScreen(),
    WeeklyReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<ActiveUser>().userId;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(animation);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: offsetAnimation,
                  child: child,
                ),
              );
            },
            child: _screens[_currentIndex],
          ),

          // Small "active user" chip on top-right (works for all screens)
          Positioned(
            top: 14,
            right: 14,
            child: SafeArea(
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SelectUserScreen()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.switch_account, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          userId,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey.shade600,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chair_alt), label: "Live"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: "Daily"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Weekly"),
        ],
      ),
    );
  }
}
