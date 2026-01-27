import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../state/active_user.dart';

class SelectUserScreen extends StatelessWidget {
  const SelectUserScreen({super.key});

  static const chairId = 'chair1';

  static const users = <String>[
    'chairUser1',
    'chairUser2',
    'chairUser3',
  ];

  @override
  Widget build(BuildContext context) {
    final activeUser = context.watch<ActiveUser>();

    return Scaffold(
      appBar: AppBar(title: const Text('Select User')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final userId = users[index];
          final selected = userId == activeUser.userId;

          return ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: selected ? Colors.blue.withOpacity(0.10) : null,
            title: Text(userId),
            trailing: selected ? const Icon(Icons.check) : null,
            onTap: () async {
              // 1) Update local state
              activeUser.setUser(userId);

              // 2) Tell the chair who is active
              await FirebaseDatabase.instance
                  .ref('chairs/$chairId/activeUserId')
                  .set(userId);

              // feedback
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Active user set to $userId')),
                );
              }
            },
          );
        },
      ),
    );
  }
}
