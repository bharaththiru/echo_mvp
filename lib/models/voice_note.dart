class VoiceNote {
  VoiceNote({
    required this.id,
    required this.hashtagId,
    required this.hashtagLabel,
    required this.createdAt,
    required this.duration,
    required this.storagePath,
    required this.allowReplies,
    required this.expiresAt,
    required this.authorId,
    this.transcriptPreview,
    this.localPath,
  });

  final String id;
  final String hashtagId;
  final String hashtagLabel;
  final DateTime createdAt;
  final Duration duration;
  final String storagePath;
  final bool allowReplies;
  final DateTime? expiresAt;
  final String? authorId;
  final String? transcriptPreview;
  final String? localPath;

  bool get expiresIn24h => expiresAt != null;

  VoiceNote copyWith({
    String? id,
    String? hashtagId,
    String? hashtagLabel,
    DateTime? createdAt,
    Duration? duration,
    String? storagePath,
    bool? allowReplies,
    DateTime? expiresAt,
    String? authorId,
    String? transcriptPreview,
    String? localPath,
  }) {
    return VoiceNote(
      id: id ?? this.id,
      hashtagId: hashtagId ?? this.hashtagId,
      hashtagLabel: hashtagLabel ?? this.hashtagLabel,
      createdAt: createdAt ?? this.createdAt,
      duration: duration ?? this.duration,
      storagePath: storagePath ?? this.storagePath,
      allowReplies: allowReplies ?? this.allowReplies,
      expiresAt: expiresAt ?? this.expiresAt,
      authorId: authorId ?? this.authorId,
      transcriptPreview: transcriptPreview ?? this.transcriptPreview,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hashtagId': hashtagId,
      'hashtagLabel': hashtagLabel,
      'createdAt': createdAt.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'storagePath': storagePath,
      'allowReplies': allowReplies,
      'expiresAt': expiresAt?.toIso8601String(),
      'authorId': authorId,
      'transcriptPreview': transcriptPreview,
      'localPath': localPath,
    };
  }

  static VoiceNote fromJson(Map<String, dynamic> json) {
    return VoiceNote(
      id: json['id'] as String,
      hashtagId: json['hashtagId'] as String,
      hashtagLabel: json['hashtagLabel'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      duration: Duration(seconds: json['durationSeconds'] as int),
      storagePath: json['storagePath'] as String,
      allowReplies: json['allowReplies'] as bool,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      authorId: json['authorId'] as String?,
      transcriptPreview: json['transcriptPreview'] as String?,
      localPath: json['localPath'] as String?,
    );
  }
}
