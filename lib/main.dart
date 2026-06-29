import 'package:flutter/material.dart';
import 'package:gitfight/app.dart';

void main() {
  runApp(const GitFightApp());
}

class GitFightApp extends StatelessWidget {
  const GitFightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Git Fight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6FB1E0),
      ),
      home: const GameScreen(),
    );
  }
}
