/// One voice note: the transcript, plus the audio file when one was kept.
class Note {
  const Note({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.lang = '',
    this.pinned = false,
    this.audioPath,
    this.durationMs = 0,
  });

  /// Epoch milliseconds when recording started, as text. Also the audio file name.
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// BCP-47 tag used for dictation ('' = device default).
  final String lang;
  final bool pinned;
  final String? audioPath;
  final int durationMs;

  bool get hasAudio => audioPath != null;

  /// First line of the transcript, for list rows.
  String get title {
    final line = text.trim().split('\n').first.trim();
    if (line.isEmpty) return hasAudio ? 'Audio memo' : 'Empty note';
    return line.length > 80 ? '${line.substring(0, 80).trimRight()}…' : line;
  }

  Note copyWith({
    String? text,
    DateTime? updatedAt,
    bool? pinned,
    String? audioPath,
    int? durationMs,
  }) {
    return Note(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lang: lang,
      pinned: pinned ?? this.pinned,
      audioPath: audioPath ?? this.audioPath,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'lang': lang,
    'pinned': pinned,
    'audioPath': audioPath,
    'durationMs': durationMs,
  };

  factory Note.fromJson(Map<String, dynamic> j) {
    final created = DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num?)?.toInt() ?? 0);
    return Note(
      id: j['id'] as String,
      text: (j['text'] as String?) ?? '',
      createdAt: created,
      updatedAt: j['updatedAt'] == null
          ? created
          : DateTime.fromMillisecondsSinceEpoch((j['updatedAt'] as num).toInt()),
      lang: (j['lang'] as String?) ?? '',
      pinned: (j['pinned'] as bool?) ?? false,
      audioPath: j['audioPath'] as String?,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}
