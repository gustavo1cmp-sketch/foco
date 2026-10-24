import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // usa google-services.json / GoogleService-Info.plist
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const FocoApp()));
}

class FocoApp extends StatelessWidget {
  const FocoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5B6CFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Foco',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
