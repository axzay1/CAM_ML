import 'captured_image.dart';

class Album {
  Album({
    required this.id,
    required this.name,
    required this.anchorLat,
    required this.anchorLng,
    required this.anchorBearing,
    required this.targetDistanceCm,
    required this.images,
  });

  final String id;
  final String name;
  final double anchorLat;
  final double anchorLng;
  final double anchorBearing;
  final double targetDistanceCm;
  final List<CapturedImage> images;

  bool get isComplete => images.length >= 4;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'anchorLat': anchorLat,
      'anchorLng': anchorLng,
      'anchorBearing': anchorBearing,
      'targetDistanceCm': targetDistanceCm,
      'images': images.map((e) => e.toMap()).toList(),
    };
  }

  factory Album.fromMap(Map<dynamic, dynamic> map) {
    final dynamic rawImages = map['images'];
    final List<CapturedImage> imageList = <CapturedImage>[];
    if (rawImages is List) {
      for (final dynamic item in rawImages) {
        if (item is Map) {
          imageList.add(CapturedImage.fromMap(item));
        }
      }
    }

    return Album(
      id: map['id'] as String,
      name: map['name'] as String,
      anchorLat: (map['anchorLat'] as num).toDouble(),
      anchorLng: (map['anchorLng'] as num).toDouble(),
      anchorBearing: (map['anchorBearing'] as num).toDouble(),
      targetDistanceCm: (map['targetDistanceCm'] as num).toDouble(),
      images: imageList,
    );
  }
}
