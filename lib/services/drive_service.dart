import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class DriveService {
  static const String requiredAccount = 'akshayscamml@gmail.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveScope],
  );

  Future<String> uploadImages({
    required List<File> files,
    required void Function(double percent) onProgress,
  }) async {
    if (files.isEmpty) {
      throw Exception('No images available for upload.');
    }

    final GoogleSignInAccount? account = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in cancelled.');
    }
    if (account.email.toLowerCase() != requiredAccount) {
      throw Exception('Please sign in with $requiredAccount.');
    }

    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) {
      throw Exception('Missing Google access token.');
    }

    final http.Client client = _GoogleAuthClient(token);
    try {
      final drive.DriveApi api = drive.DriveApi(client);

      final drive.File folderMeta = drive.File()
        ..name = 'CAM_ML_${DateTime.now().millisecondsSinceEpoch}'
        ..mimeType = 'application/vnd.google-apps.folder';

      final drive.File createdFolder = await api.files.create(folderMeta);
      final String? folderId = createdFolder.id;
      if (folderId == null) {
        throw Exception('Failed to create Drive folder.');
      }

      for (int i = 0; i < files.length; i++) {
        final File file = files[i];
        final String name = file.path.split(Platform.pathSeparator).last;
        final int length = await file.length();
        final drive.Media media = drive.Media(file.openRead(), length);

        final drive.File fileMeta = drive.File()
          ..name = name
          ..parents = <String>[folderId];

        await api.files.create(fileMeta, uploadMedia: media);
        onProgress(((i + 1) / files.length) * 100.0);
      }

      await api.permissions.create(
        drive.Permission()
          ..role = 'reader'
          ..type = 'anyone',
        folderId,
      );

      return 'https://drive.google.com/drive/folders/$folderId';
    } finally {
      client.close();
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
