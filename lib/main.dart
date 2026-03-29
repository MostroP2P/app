import 'package:flutter/material.dart';

void main() {
  runApp(const MostroApp());
}

class MostroApp extends StatelessWidget {
  const MostroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Mostro',
      home: Scaffold(
        body: Center(
          child: Text('Mostro Mobile v2'),
        ),
      ),
    );
  }
}
