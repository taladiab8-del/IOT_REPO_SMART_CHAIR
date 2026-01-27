import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'state/active_user.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: 'chair@chair.com',
    password: '12345678',
);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ActiveUser(),
     child: const SmartChairApp(),
    ),
  );
}

class SmartChairApp extends StatelessWidget {
  const SmartChairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Chair',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.mixedTheme,
      home: const SplashScreen(),
    );
  }
}
