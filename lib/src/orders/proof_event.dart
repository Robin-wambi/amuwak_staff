enum ProofEventType { pickup, delivery }

class ProofEvent {
  const ProofEvent({
    required this.id,
    required this.type,
    required this.capturedAt,
    required this.count,
    required this.photoPaths,
    this.notes,
  });

  final String id;
  final ProofEventType type;
  final DateTime capturedAt;
  final int count;
  final List<String> photoPaths;
  final String? notes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProofEvent) return false;
    if (id != other.id) return false;
    if (type != other.type) return false;
    if (capturedAt != other.capturedAt) return false;
    if (count != other.count) return false;
    if (notes != other.notes) return false;
    if (photoPaths.length != other.photoPaths.length) return false;
    for (var i = 0; i < photoPaths.length; i++) {
      if (photoPaths[i] != other.photoPaths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        capturedAt,
        count,
        notes,
        Object.hashAll(photoPaths),
      );
}
