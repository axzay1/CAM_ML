import 'package:flutter_compass/flutter_compass.dart';

class CompassService {
  static Stream<double> headingStream() {
    return FlutterCompass.events?.map((event) => event.heading ?? 0.0) ?? Stream.value(0.0);
  }
}
