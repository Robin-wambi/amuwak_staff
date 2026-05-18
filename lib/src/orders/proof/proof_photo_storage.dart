import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../proof_event.dart';

/// Computes the `minWidth` / `minHeight` pair to pass to
/// `FlutterImageCompress.compressWithList` so that the LONGER edge of the
/// result is at most [maxEdge] pixels, preserving aspect ratio.
///
/// The package's own `minWidth` / `minHeight` parameters together cap the
/// SHORTER edge, not the longer one — passing `(maxEdge, maxEdge)` for a
/// 4000×3000 source yields ~1707×1280, not 1280×960. Computing the pair from
/// the source dimensions makes 1280 mean "longest edge ≤ 1280" as intended.
({int minWidth, int minHeight}) compressTargetForMaxEdge({
  required int width,
  required int height,
  required int maxEdge,
}) {
  if (width >= height) {
    return (
      minWidth: maxEdge,
      minHeight: (maxEdge * height / width).round(),
    );
  }
  return (
    minWidth: (maxEdge * width / height).round(),
    minHeight: maxEdge,
  );
}

typedef PickPhotoFn = Future<List<int>?> Function();

abstract class ProofPhotoStorage {
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  });
}

class SavedProofPhoto {
  const SavedProofPhoto({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;
}

class InMemoryProofPhotoStorage implements ProofPhotoStorage {
  InMemoryProofPhotoStorage();

  final List<SavedProofPhoto> savedPhotos = [];

  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    final path = 'memory://$orderId/${type.name}_$index';
    savedPhotos.add(SavedProofPhoto(path: path, bytes: bytes));
    return path;
  }
}

typedef PhotoCompressor = Future<Uint8List> Function(Uint8List bytes);

class FileProofPhotoStorage implements ProofPhotoStorage {
  FileProofPhotoStorage({
    required this.baseDir,
    required this.compressor,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory baseDir;
  final PhotoCompressor compressor;
  final DateTime Function() _clock;

  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    final orderDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}proofs${Platform.pathSeparator}$orderId',
    );
    if (!await orderDir.exists()) {
      await orderDir.create(recursive: true);
    }
    final compressed = await compressor(Uint8List.fromList(bytes));
    final filename =
        '${type.name}_${_clock().millisecondsSinceEpoch}_$index.jpg';
    final file = File('${orderDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(compressed);
    return file.path;
  }
}

/// Production factory: resolves the app documents directory via path_provider
/// and uses flutter_image_compress to shrink images so the longer edge is
/// capped at 1280 pixels (JPEG quality 80). Images smaller than the cap pass
/// through untouched — flutter_image_compress never upscales.
Future<FileProofPhotoStorage> createDefaultProofPhotoStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  return FileProofPhotoStorage(
    baseDir: dir,
    compressor: (bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final target = compressTargetForMaxEdge(
        width: image.width,
        height: image.height,
        maxEdge: 1280,
      );
      image.dispose();
      codec.dispose();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: target.minWidth,
        minHeight: target.minHeight,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return result;
    },
  );
}
