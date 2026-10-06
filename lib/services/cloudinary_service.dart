// ============================================================
// lib/services/cloudinary_service.dart
//
// Image hosting via Cloudinary's free tier (25 GB storage,
// 25 GB/month bandwidth, no card required) — chosen specifically
// because Firebase Storage now requires a Blaze (billing-enabled)
// plan even within free-tier usage limits, which this project's
// owner wants to avoid for a student/FYP deployment.
//
// HOW THIS WORKS:
//   Cloudinary supports "unsigned" uploads — the app uploads
//   directly to Cloudinary's REST API using only a public cloud
//   name + a pre-configured unsigned upload preset, with NO API
//   secret embedded in the app. This is the officially-supported
//   pattern for client-side/mobile uploads (the alternative, signed
//   uploads, requires a backend to generate a signature, which this
//   project does not have and does not need).
//
// SECURITY NOTE (documented, not a TODO):
//   Anyone who decompiles this APK could find the cloud name and
//   preset name and upload arbitrary files to this Cloudinary
//   account. This is an accepted limitation of unsigned uploads on
//   any client-only app without a backend — mitigated by:
//     - the preset only allowing image uploads (configured in
//       Cloudinary console)
//     - Firestore Security Rules already restricting who can write
//       a `products` document with an imageUrl pointing elsewhere
//     - the free-tier usage caps limiting blast radius
//   If this app ever gets a backend, migrate to signed uploads.
// ============================================================
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CloudinaryService {
  // ── Your Cloudinary account, confirmed working with this preset ───────
  static const String _cloudName    = 'devyxiwhc';
  static const String _uploadPreset = 'ml_default';

  static Uri get _uploadEndpoint => Uri.parse(
    'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
  );

  /// Uploads [imageFile] to Cloudinary and returns the resulting
  /// secure HTTPS URL (e.g. https://res.cloudinary.com/devyxiwhc/...).
  ///
  /// [folder] groups uploads in the Cloudinary Media Library (e.g.
  /// 'products') purely for organization — it has no effect on app
  /// behavior, just makes the Cloudinary console easier to browse.
  ///
  /// Throws an [Exception] with a user-presentable message on failure
  /// (network error, Cloudinary rejecting the file, etc.) — callers
  /// should wrap this in their own try/catch and show the message,
  /// exactly like PaymentService.recordPayment's error convention.
  Future<String> uploadImage(File imageFile, {String folder = 'products'}) async {
    try {
      final request = http.MultipartRequest('POST', _uploadEndpoint)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder']        = folder
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        final body = _tryDecodeError(response.body);
        throw Exception(body ?? 'Image upload failed (HTTP ${response.statusCode}).');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url  = data['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Cloudinary did not return an image URL.');
      }
      return url;
    } on http.ClientException {
      throw Exception('Could not reach the image server. Check your internet connection.');
    } on FormatException {
      throw Exception('Unexpected response from the image server.');
    }
  }

  String? _tryDecodeError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final err  = data['error'] as Map<String, dynamic>?;
      return err?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}