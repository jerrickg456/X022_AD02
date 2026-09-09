import 'package:flutter/material.dart';
import 'theme.dart';
import 'routes.dart';

class SonicMeshApp extends StatelessWidget {
  const SonicMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SonicMesh',
      debugShowCheckedModeBanner: false,
      theme: SonicTheme.darkTheme,
      initialRoute: Routes.home,
      routes: Routes.routes,
    );
  }
}
