import 'package:hive_flutter/hive_flutter.dart';

import '../models/album.dart';

class AlbumService {
  static const String _boxName = 'cam_ml_albums';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
  }

  Future<void> saveAlbum(Album album) async {
    await init();
    await _box!.put(album.id, album.toMap());
  }

  List<Album> getAllAlbums() {
    if (_box == null) {
      return <Album>[];
    }
    return _box!.values
        .whereType<Map>()
        .map((value) => Album.fromMap(value))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  Future<void> deleteAlbum(String id) async {
    await init();
    await _box!.delete(id);
  }
}
