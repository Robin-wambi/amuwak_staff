import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../proof_event.dart';

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
/// and uses flutter_image_compress to shrink images to 1280px max edge at
/// JPEG quality 80.
Future<FileProofPhotoStorage> createDefaultProofPhotoStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  return FileProofPhotoStorage(
    baseDir: dir,
    compressor: (bytes) async {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return result;
    },
  );
}
