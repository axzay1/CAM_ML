import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'providers/camera_provider.dart';
import 'screens/camera_screen.dart';
import 'screens/tutorial_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final prefsBox = await Hive.openBox<dynamic>('cam_ml_prefs');
  final bool tutorialSeen =
      prefsBox.get('tutorial_seen', defaultValue: false) as bool;

  await [
    Permission.camera,
    Permission.locationWhenInUse,
    Permission.sensors,
  ].request();

  runApp(MyApp(showTutorial: !tutorialSeen));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showTutorial = false});

  final bool showTutorial;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CameraProvider(),
      child: MaterialApp(
        title: 'CAM ML',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.teal,
          scaffoldBackgroundColor: Colors.black,
        ),
        home: showTutorial ? const TutorialScreen() : const CameraScreen(),
      ),
    );
  }
}
