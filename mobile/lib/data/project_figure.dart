import 'dart:convert';
import 'dart:typed_data';

/// Placement mode for a figure in an academic manuscript.
enum FigurePlacement {
  /// Fits within a single column (default for both single and two-column layouts).
  columnWidth('column_width'),

  /// Spans across the entire page / both columns in two-column layouts.
  fullWidth('full_width');

  final String value;
  const FigurePlacement(this.value);

  static FigurePlacement fromString(String? raw) {
    if (raw == 'full_width') return FigurePlacement.fullWidth;
    return FigurePlacement.columnWidth;
  }
}

/// Durable academic manuscript figure model.
class ProjectFigure {
  ProjectFigure({
    required this.id,
    required this.projectId,
    required this.figureNumber,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.caption,
    required this.storageKey,
    this.width = 0,
    this.height = 0,
    this.altText = '',
    this.placement = FigurePlacement.columnWidth,
    this.sectionId,
    this.category = 'other',
    this.title,
    this.targetAnchor,
    this.placementRationale,
    this.preferredPlacement = 'after_paragraph',
    this.referencedInText = false,
    this.placementStatus = 'unplaced',
    DateTime? createdAt,
    this.cachedBytes,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String projectId;
  final int figureNumber;
  final String filename;
  final String mimeType;
  final int width;
  final int height;
  final int fileSize;
  final String caption;
  final String altText;
  final FigurePlacement placement;
  final String? sectionId;
  final String storageKey;
  final String category;
  final String? title;
  final String? targetAnchor;
  final String? placementRationale;
  final String preferredPlacement;
  final bool referencedInText;
  final String placementStatus;
  final DateTime createdAt;
  final Uint8List? cachedBytes;

  /// Generate a standard data URI string from bytes.
  static String formatDataUri(String mimeType, Uint8List bytes) =>
      'data:$mimeType;base64,${base64Encode(bytes)}';

  /// Serialize to a database row for the `project_figures` table.
  Map<String, Object?> toDatabaseRow() => {
    'id': id,
    'project_id': projectId,
    'figure_number': figureNumber,
    'filename': filename,
    'mime_type': mimeType,
    'width': width,
    'height': height,
    'file_size': fileSize,
    'caption': caption,
    'alt_text': altText,
    'placement': placement.value,
    'section_id': sectionId,
    'storage_key': storageKey,
    'created_at': createdAt.toIso8601String(),
  };

  /// Create from a database row in `project_figures`.
  factory ProjectFigure.fromDatabaseRow(Map<String, Object?> row) => ProjectFigure(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    figureNumber: (row['figure_number'] as num?)?.toInt() ?? 1,
    filename: row['filename'] as String? ?? 'figure',
    mimeType: row['mime_type'] as String? ?? 'image/png',
    width: (row['width'] as num?)?.toInt() ?? 0,
    height: (row['height'] as num?)?.toInt() ?? 0,
    fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
    caption: row['caption'] as String? ?? '',
    altText: row['alt_text'] as String? ?? '',
    placement: FigurePlacement.fromString(row['placement'] as String?),
    sectionId: row['section_id'] as String?,
    category: row['category'] as String? ?? 'other',
    title: row['title'] as String?,
    targetAnchor: row['target_anchor'] as String?,
    placementRationale: row['placement_rationale'] as String?,
    preferredPlacement: row['preferred_placement'] as String? ?? 'after_paragraph',
    referencedInText: (row['referenced_in_text'] as num?)?.toInt() == 1,
    placementStatus: row['placement_status'] as String? ?? 'unplaced',
    storageKey: row['storage_key'] as String? ?? '',
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  /// Structured Figure representation matching backend wire contract.
  Map<String, Object?> toStructuredFigureMap() => {
    'id': id,
    'filename': filename,
    'caption': caption,
    if (storageKey.isNotEmpty) 'storage_key': storageKey,
    if (cachedBytes != null) 'data_uri': formatDataUri(mimeType, cachedBytes!),
    'width': width,
    'height': height,
    'mime_type': mimeType,
    if (title != null) 'title': title,
    if (altText.isNotEmpty) 'description': altText,
    'category': category,
    if (sectionId != null) 'related_section': sectionId,
    if (targetAnchor != null) 'target_anchor': targetAnchor,
    if (placementRationale != null) 'placement_rationale': placementRationale,
    'preferred_placement': preferredPlacement,
    'column_span': placement.value,
    'figure_order': figureNumber,
    'referenced_in_text': referencedInText,
    'placement_status': placementStatus,
  };

  /// Lightweight metadata representation safe for `project_context_json` without giant byte arrays.
  Map<String, Object?> toMetadataMap() => {
    'id': id,
    'name': filename,
    'caption': caption,
    'description': altText.isNotEmpty ? altText : 'Figure: $caption',
    'placement': placement.value,
    'storage_key': storageKey,
    'mime_type': mimeType,
    'file_size': fileSize,
    'width': width,
    'height': height,
    'category': category,
    if (title != null) 'title': title,
    if (sectionId != null) 'section_id': sectionId,
    if (targetAnchor != null) 'target_anchor': targetAnchor,
    if (placementRationale != null) 'placement_rationale': placementRationale,
    'preferred_placement': preferredPlacement,
    'referenced_in_text': referencedInText,
    'placement_status': placementStatus,
  };

  /// Reconstitute from a project context map (handling both new and legacy formats).
  factory ProjectFigure.fromMap(
    Map<String, dynamic> map, {
    required String projectId,
    int defaultNumber = 1,
  }) {
    final rawPlacement = map['placement'] as String?;
    final id = map['id']?.toString() ?? 'fig_$defaultNumber';
    final name = map['name']?.toString() ?? map['filename']?.toString() ?? 'figure.png';
    final caption = map['caption']?.toString() ?? 'Figure $defaultNumber';
    final altText = map['alt_text']?.toString() ?? map['description']?.toString() ?? '';
    final mimeType = map['mime_type']?.toString() ?? _inferMimeType(name);
    final storageKey = map['storage_key']?.toString() ?? '$projectId/${id}_$name';
    final width = (map['width'] as num?)?.toInt() ?? 0;
    final height = (map['height'] as num?)?.toInt() ?? 0;
    final category = map['category']?.toString() ?? 'other';
    final title = map['title']?.toString();
    final targetAnchor = map['target_anchor']?.toString();
    final placementRationale = map['placement_rationale']?.toString();
    final preferredPlacement = map['preferred_placement']?.toString() ?? 'after_paragraph';
    final referencedInText = map['referenced_in_text'] == true || map['referenced_in_text'] == 1;
    final placementStatus = map['placement_status']?.toString() ?? 'unplaced';

    Uint8List? bytes;
    if (map['bytes'] is Uint8List) {
      bytes = map['bytes'] as Uint8List;
    } else if (map['bytes'] is List) {
      bytes = Uint8List.fromList((map['bytes'] as List).cast<int>());
    } else if (map['base64'] is String && (map['base64'] as String).isNotEmpty) {
      final b64 = map['base64'] as String;
      final commaIdx = b64.indexOf(',');
      final cleanB64 = commaIdx >= 0 ? b64.substring(commaIdx + 1) : b64;
      try {
        bytes = base64Decode(cleanB64.trim());
      } catch (_) {}
    } else if (map['data_uri'] is String && (map['data_uri'] as String).isNotEmpty) {
      final du = map['data_uri'] as String;
      final commaIdx = du.indexOf(',');
      final cleanB64 = commaIdx >= 0 ? du.substring(commaIdx + 1) : du;
      try {
        bytes = base64Decode(cleanB64.trim());
      } catch (_) {}
    }

    final fileSize = (map['file_size'] as num?)?.toInt() ?? (bytes?.length ?? 0);

    return ProjectFigure(
      id: id,
      projectId: projectId,
      figureNumber: (map['figure_number'] as num?)?.toInt() ?? defaultNumber,
      filename: name,
      mimeType: mimeType,
      width: width,
      height: height,
      fileSize: fileSize,
      caption: caption,
      altText: altText,
      placement: FigurePlacement.fromString(rawPlacement),
      sectionId: map['section_id']?.toString() ?? map['related_section']?.toString(),
      category: category,
      title: title,
      targetAnchor: targetAnchor,
      placementRationale: placementRationale,
      preferredPlacement: preferredPlacement,
      referencedInText: referencedInText,
      placementStatus: placementStatus,
      storageKey: storageKey,
      cachedBytes: bytes,
    );
  }

  ProjectFigure copyWith({
    String? id,
    String? projectId,
    int? figureNumber,
    String? filename,
    String? mimeType,
    int? width,
    int? height,
    int? fileSize,
    String? caption,
    String? altText,
    FigurePlacement? placement,
    String? sectionId,
    String? category,
    String? title,
    String? targetAnchor,
    String? placementRationale,
    String? preferredPlacement,
    bool? referencedInText,
    String? placementStatus,
    String? storageKey,
    DateTime? createdAt,
    Uint8List? cachedBytes,
  }) => ProjectFigure(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    figureNumber: figureNumber ?? this.figureNumber,
    filename: filename ?? this.filename,
    mimeType: mimeType ?? this.mimeType,
    width: width ?? this.width,
    height: height ?? this.height,
    fileSize: fileSize ?? this.fileSize,
    caption: caption ?? this.caption,
    altText: altText ?? this.altText,
    placement: placement ?? this.placement,
    sectionId: sectionId ?? this.sectionId,
    category: category ?? this.category,
    title: title ?? this.title,
    targetAnchor: targetAnchor ?? this.targetAnchor,
    placementRationale: placementRationale ?? this.placementRationale,
    preferredPlacement: preferredPlacement ?? this.preferredPlacement,
    referencedInText: referencedInText ?? this.referencedInText,
    placementStatus: placementStatus ?? this.placementStatus,
    storageKey: storageKey ?? this.storageKey,
    createdAt: createdAt ?? this.createdAt,
    cachedBytes: cachedBytes ?? this.cachedBytes,
  );

  static String _inferMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'image/png',
    };
  }
}
