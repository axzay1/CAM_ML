import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

// ── Embedded credentials for akshayscamml@gmail.com ──────────────────────────
// These never change unless you revoke access or rotate the client secret.
//
// To generate once:
//   1. console.cloud.google.com → APIs & Services → Credentials
//      → Create OAuth 2.0 Client ID → "Desktop app"
//   2. Enable the Google Drive API in the same project.
//   3. Visit this URL in a browser signed in as akshayscamml@gmail.com:
//        https://accounts.google.com/o/oauth2/v2/auth
//          ?client_id=<CLIENT_ID>
//          &redirect_uri=urn:ietf:wg:oauth:2.0:oob
//          &response_type=code
//          &scope=https://www.googleapis.com/auth/drive
//          &access_type=offline&prompt=consent
//   4. Copy the code, then run:
//        curl -X POST https://oauth2.googleapis.com/token \
//          -d "code=CODE&client_id=CLIENT_ID&client_secret=CLIENT_SECRET
//              &redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code"
//   5. Paste the refresh_token below.
// TODO: fill these in before shipping (see comment block above for steps)
const String _kClientId = 'YOUR_CLIENT_ID';
const String _kClientSecret = 'YOUR_CLIENT_SECRET';
const String _kRefreshToken = 'YOUR_REFRESH_TOKEN';

class DriveService {
  Future<String> _accessToken() async {
    final resp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': _kClientId,
        'client_secret': _kClientSecret,
        'refresh_token': _kRefreshToken,
        'grant_type': 'refresh_token',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Drive auth failed (${resp.statusCode}): ${resp.body}');
    }
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    return json['access_token'] as String;
  }

  Future<String> uploadImages({
    required List<File> files,
    required void Function(double percent) onProgress,
  }) async {
    if (files.isEmpty) throw Exception('No images to upload.');

    final String token = await _accessToken();
    final http.Client client = _AuthClient(token);
    try {
      final drive.DriveApi api = drive.DriveApi(client);

      final drive.File folderMeta = drive.File()
        ..name = 'CAM_ML_${DateTime.now().millisecondsSinceEpoch}'
        ..mimeType = 'application/vnd.google-apps.folder';

      final drive.File created = await api.files.create(folderMeta);
      final String? folderId = created.id;
      if (folderId == null) throw Exception('Failed to create Drive folder.');

      for (int i = 0; i < files.length; i++) {
        final File f = files[i];
        final drive.File meta = drive.File()
          ..name = f.path.split(Platform.pathSeparator).last
          ..parents = [folderId];
        await api.files.create(
          meta,
          uploadMedia: drive.Media(f.openRead(), await f.length()),
        );
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

class _AuthClient extends http.BaseClient {
  _AuthClient(this._token);
  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
