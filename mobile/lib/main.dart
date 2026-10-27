import 'package:flutter/material.dart';

void main() {
  runApp(const ResbudApp());
}

class ResbudApp extends StatelessWidget {
  const ResbudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resbud',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const Scaffold(
        body: Center(
          child: Text('Resbud'),
        ),
      ),
    );
  }
}
