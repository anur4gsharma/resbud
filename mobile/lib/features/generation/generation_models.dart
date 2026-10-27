import 'dart:convert';

final _sectionIdPattern = RegExp(r'^[a-z][a-z0-9_]{1,39}$');
final _referenceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

class GenerationRequest {
  const GenerationRequest({
    required this.project,
    required this.sourceDraft,
    required this.references,
    required this.preferences,
  });

  final ProjectContextPayload project;
  final String sourceDraft;
  final List<ReferencePayload> references;
  final PaperPreferencesPayload preferences;

  factory GenerationRequest.fromInputs({
    required Map<String, Object?> project,
    required String sourceDraft,
  }) {
    final context = Map<String, Object?>.from(project)
      ..remove('references')
      ..remove('preferences');
    final projectPayload = ProjectContextPayload.fromJson(context);
    final references = _list(project['references'], 'project.references')
        .map((value) => ReferencePayload.fromJson(_map(value, 'reference')))
        .toList(growable: false);
    final preferences = PaperPreferencesPayload.fromJson(
      _map(project['preferences'], 'project.preferences'),
    );
    if (sourceDraft.trim().isEmpty || sourceDraft.length > 50000) {
      throw const FormatException('Source draft must contain 1–50,000 characters.');
    }
    if (references.length > 50) {
      throw const FormatException('There can be no more than 50 references.');
    }
    return GenerationRequest(
      project: projectPayload,
      sourceDraft: sourceDraft,
      references: references,
      preferences: preferences,
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'project': project.toJson(),
    'source_draft': sourceDraft,
    'references': references.map((reference) => reference.toJson()).toList(),
    'preferences': preferences.toJson(),
  };

  String encode() => jsonEncode(toJson());
}

class ProjectContextPayload {
  const ProjectContextPayload({
    required this.title,
    required this.researchField,
    required this.researchQuestion,
    required this.objectives,
    required this.claimedContribution,
    required this.methodologyStatus,
    required this.methodology,
    required this.datasetOrMaterialsStatus,
    required this.datasetOrMaterials,
    required this.resultsStatus,
    required this.results,
    required this.limitationsStatus,
    required this.limitations,
  });

  final String title;
  final String researchField;
  final String researchQuestion;
  final List<String> objectives;
  final String claimedContribution;
  final String methodologyStatus;
  final String? methodology;
  final String datasetOrMaterialsStatus;
  final String? datasetOrMaterials;
  final String resultsStatus;
  final String? results;
  final String limitationsStatus;
  final String? limitations;

  factory ProjectContextPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {
      'title',
      'research_field',
      'research_question',
      'objectives',
      'claimed_contribution',
      'methodology_status',
      'dataset_or_materials_status',
      'results_status',
      'limitations_status',
    },
    'project',
    optional: const {
      'methodology',
      'dataset_or_materials',
      'results',
      'limitations',
    },
    );
    final objectives = _list(json['objectives'], 'objectives')
        .map((value) => _string(value, 'objective'))
        .toList(growable: false);
    if (objectives.isEmpty || objectives.length > 20) {
      throw const FormatException('Add 1–20 objectives.');
    }
    for (final objective in objectives) {
      if (objective.trim().isEmpty || objective.length > 1000) {
        throw const FormatException('Each objective must contain 1–1,000 characters.');
      }
    }
    final payload = ProjectContextPayload(
      title: _boundedString(json['title'], 'title', 1, 300),
      researchField: _boundedString(json['research_field'], 'research_field', 1, 200),
      researchQuestion: _boundedString(json['research_question'], 'research_question', 1, 4000),
      objectives: objectives,
      claimedContribution: _boundedString(json['claimed_contribution'], 'claimed_contribution', 0, 4000),
      methodologyStatus: _enumValue(json['methodology_status'], 'methodology_status', const [
        'provided', 'not_available', 'not_applicable', 'unknown',
      ]),
      methodology: _optionalBoundedString(json['methodology'], 'methodology', 12000),
      datasetOrMaterialsStatus: _enumValue(json['dataset_or_materials_status'], 'dataset_or_materials_status', const [
        'provided', 'not_available', 'not_applicable', 'unknown',
      ]),
      datasetOrMaterials: _optionalBoundedString(json['dataset_or_materials'], 'dataset_or_materials', 8000),
      resultsStatus: _enumValue(json['results_status'], 'results_status', const [
        'provided', 'not_collected', 'not_available', 'not_applicable', 'unknown',
      ]),
      results: _optionalBoundedString(json['results'], 'results', 12000),
      limitationsStatus: _enumValue(json['limitations_status'], 'limitations_status', const [
        'provided', 'not_identified', 'not_available', 'not_applicable', 'unknown',
      ]),
      limitations: _optionalBoundedString(json['limitations'], 'limitations', 8000),
    );
    for (final pair in [
      (payload.methodologyStatus, payload.methodology, 'methodology'),
      (payload.datasetOrMaterialsStatus, payload.datasetOrMaterials, 'dataset_or_materials'),
      (payload.resultsStatus, payload.results, 'results'),
      (payload.limitationsStatus, payload.limitations, 'limitations'),
    ]) {
      if (pair.$1 == 'provided' && (pair.$2 == null || pair.$2!.trim().isEmpty)) {
        throw FormatException('${pair.$3} is required when its status is provided.');
      }
    }
    return payload;
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'research_field': researchField,
    'research_question': researchQuestion,
    'objectives': objectives,
    'claimed_contribution': claimedContribution,
    'methodology_status': methodologyStatus,
    if (methodology != null) 'methodology': methodology,
    'dataset_or_materials_status': datasetOrMaterialsStatus,
    if (datasetOrMaterials != null) 'dataset_or_materials': datasetOrMaterials,
    'results_status': resultsStatus,
    if (results != null) 'results': results,
    'limitations_status': limitationsStatus,
    if (limitations != null) 'limitations': limitations,
  };
}

class ReferencePayload {
  const ReferencePayload({required this.id, required this.text});

  final String id;
  final String text;

  factory ReferencePayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {'id', 'text'}, 'reference');
    final id = _boundedString(json['id'], 'reference.id', 1, 40);
    if (!_referenceIdPattern.hasMatch(id)) {
      throw const FormatException('Reference IDs may use letters, numbers, underscores, and hyphens.');
    }
    return ReferencePayload(
      id: id,
      text: _boundedString(json['text'], 'reference.text', 1, 2000),
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

class PaperPreferencesPayload {
  const PaperPreferencesPayload({
    required this.targetWordCount,
    required this.desiredSections,
    required this.citationStyle,
  });

  final int targetWordCount;
  final List<String> desiredSections;
  final String citationStyle;

  factory PaperPreferencesPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {
      'target_word_count',
      'desired_sections',
      'citation_style',
    }, 'preferences');
    final wordCount = _integer(json['target_word_count'], 'target_word_count');
    if (wordCount < 500 || wordCount > 8000) {
      throw const FormatException('Target word count must be between 500 and 8,000.');
    }
    final sections = _list(json['desired_sections'], 'desired_sections')
        .map((value) => _string(value, 'desired section'))
        .toList(growable: false);
    if (sections.length > 15 || sections.toSet().length != sections.length ||
        sections.any((section) => !_sectionIdPattern.hasMatch(section))) {
      throw const FormatException('Choose up to 15 unique valid section IDs.');
    }
    return PaperPreferencesPayload(
      targetWordCount: wordCount,
      desiredSections: sections,
      citationStyle: _enumValue(json['citation_style'], 'citation_style', const [
        'user_supplied', 'apa_7', 'ieee', 'other',
      ]),
    );
  }

  Map<String, Object?> toJson() => {
    'target_word_count': targetWordCount,
    'desired_sections': desiredSections,
    'citation_style': citationStyle,
  };
}

class GenerationResponse {
  const GenerationResponse({
    required this.generationId,
    required this.paper,
    required this.reviewWarnings,
    required this.meta,
  });

  final String generationId;
  final PaperDraftPayload paper;
  final List<ReviewWarningPayload> reviewWarnings;
  final GenerationMetaPayload meta;

  factory GenerationResponse.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {
      'schema_version', 'generation_id', 'paper', 'review_warnings', 'meta',
    }, 'generation response');
    if (_integer(json['schema_version'], 'schema_version') != 1) {
      throw const FormatException('Unsupported generation response schema version.');
    }
    final id = _string(json['generation_id'], 'generation_id');
    if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$').hasMatch(id)) {
      throw const FormatException('generation_id must be a UUID.');
    }
    final paper = PaperDraftPayload.fromJson(_map(json['paper'], 'paper'));
    final warnings = _list(json['review_warnings'], 'review_warnings')
        .map((value) => ReviewWarningPayload.fromJson(_map(value, 'review warning')))
        .toList(growable: false);
    if (warnings.length > 100 || !_sameWarnings(warnings, paper.reviewWarnings)) {
      throw const FormatException('Response warnings must match the warnings on the paper.');
    }
    return GenerationResponse(
      generationId: id,
      paper: paper,
      reviewWarnings: warnings,
      meta: GenerationMetaPayload.fromJson(_map(json['meta'], 'meta')),
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'generation_id': generationId,
    'paper': paper.toJson(),
    'review_warnings': reviewWarnings.map((warning) => warning.toJson()).toList(),
    'meta': meta.toJson(),
  };
}

class PaperDraftPayload {
  const PaperDraftPayload({
    required this.schemaVersion,
    required this.title,
    required this.abstractText,
    required this.keywords,
    required this.sections,
    required this.references,
    required this.reviewWarnings,
  });

  final int schemaVersion;
  final String title;
  final String abstractText;
  final List<String> keywords;
  final List<PaperSectionPayload> sections;
  final List<ReferencePayload> references;
  final List<ReviewWarningPayload> reviewWarnings;

  factory PaperDraftPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {
      'schema_version', 'title', 'abstract', 'keywords', 'sections', 'references', 'review_warnings',
    }, 'paper');
    if (_integer(json['schema_version'], 'paper.schema_version') != 1) {
      throw const FormatException('Unsupported paper schema version.');
    }
    final keywords = _list(json['keywords'], 'keywords')
        .map((value) => _boundedString(value, 'keyword', 1, 100))
        .toList(growable: false);
    final sections = _list(json['sections'], 'sections')
        .map((value) => PaperSectionPayload.fromJson(_map(value, 'section')))
        .toList(growable: false);
    final references = _list(json['references'], 'paper.references')
        .map((value) => ReferencePayload.fromJson(_map(value, 'paper reference')))
        .toList(growable: false);
    final warnings = _list(json['review_warnings'], 'paper.review_warnings')
        .map((value) => ReviewWarningPayload.fromJson(_map(value, 'paper warning')))
        .toList(growable: false);
    if (keywords.length > 10 || sections.isEmpty || sections.length > 15 ||
        sections.map((section) => section.id).toSet().length != sections.length ||
        references.length > 50 || warnings.length > 100) {
      throw const FormatException('The generated paper exceeds schema limits.');
    }
    return PaperDraftPayload(
      schemaVersion: 1,
      title: _boundedString(json['title'], 'paper.title', 1, 300),
      abstractText: _boundedString(json['abstract'], 'paper.abstract', 0, 6000),
      keywords: keywords,
      sections: sections,
      references: references,
      reviewWarnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'title': title,
    'abstract': abstractText,
    'keywords': keywords,
    'sections': sections.map((section) => section.toJson()).toList(),
    'references': references.map((reference) => reference.toJson()).toList(),
    'review_warnings': reviewWarnings.map((warning) => warning.toJson()).toList(),
  };
}

class PaperSectionPayload {
  const PaperSectionPayload({
    required this.id,
    required this.heading,
    required this.content,
    required this.state,
  });

  final String id;
  final String heading;
  final String content;
  final String state;

  factory PaperSectionPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {'id', 'heading', 'content', 'state'}, 'section');
    final id = _boundedString(json['id'], 'section.id', 2, 40);
    if (!_sectionIdPattern.hasMatch(id)) throw const FormatException('Invalid section ID.');
    return PaperSectionPayload(
      id: id,
      heading: _boundedString(json['heading'], 'section.heading', 1, 150),
      content: _boundedString(json['content'], 'section.content', 0, 30000),
      state: _enumValue(json['state'], 'section.state', const [
        'draft', 'needs_input', 'not_applicable',
      ]),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id, 'heading': heading, 'content': content, 'state': state,
  };
}

class ReviewWarningPayload {
  const ReviewWarningPayload({
    required this.code,
    required this.severity,
    required this.message,
    required this.sectionId,
  });

  final String code;
  final String severity;
  final String message;
  final String? sectionId;

  factory ReviewWarningPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(
      json,
      const {'code', 'severity', 'message'},
      'warning',
      optional: const {'section_id'},
    );
    final sectionId = json['section_id'] == null
        ? null
        : _boundedString(json['section_id'], 'warning.section_id', 2, 40);
    if (sectionId != null && !_sectionIdPattern.hasMatch(sectionId)) {
      throw const FormatException('Invalid warning section ID.');
    }
    return ReviewWarningPayload(
      code: _enumValue(json['code'], 'warning.code', const [
        'MISSING_METHOD', 'MISSING_DATASET_DETAILS', 'MISSING_RESULTS',
        'MISSING_LIMITATIONS', 'CITATION_NEEDED', 'REFERENCE_INCOMPLETE',
        'CLAIM_NEEDS_REVIEW', 'INPUT_CONFLICT', 'SECTION_NOT_APPLICABLE',
        'GENERAL_REVIEW',
      ]),
      severity: _enumValue(json['severity'], 'warning.severity', const [
        'info', 'warning', 'critical',
      ]),
      message: _boundedString(json['message'], 'warning.message', 1, 1000),
      sectionId: sectionId,
    );
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity,
    'message': message,
    'section_id': sectionId,
  };

  String signature() => jsonEncode(toJson());
}

class GenerationMetaPayload {
  const GenerationMetaPayload({
    required this.providerName,
    required this.modelName,
    required this.durationMs,
    required this.inputTokens,
    required this.outputTokens,
  });

  final String providerName;
  final String modelName;
  final int durationMs;
  final int? inputTokens;
  final int? outputTokens;

  factory GenerationMetaPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const {
      'provider_name', 'model_name', 'duration_ms',
    }, 'meta', optional: const {'input_tokens', 'output_tokens'});
    final duration = _integer(json['duration_ms'], 'meta.duration_ms');
    final inputTokens = json['input_tokens'] == null
        ? null
        : _integer(json['input_tokens'], 'meta.input_tokens');
    final outputTokens = json['output_tokens'] == null
        ? null
        : _integer(json['output_tokens'], 'meta.output_tokens');
    if (duration < 0 || (inputTokens != null && inputTokens < 0) ||
        (outputTokens != null && outputTokens < 0)) {
      throw const FormatException('Generation metadata counts cannot be negative.');
    }
    return GenerationMetaPayload(
      providerName: _boundedString(json['provider_name'], 'meta.provider_name', 0, 100),
      modelName: _boundedString(json['model_name'], 'meta.model_name', 0, 100),
      durationMs: duration,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }

  Map<String, Object?> toJson() => {
    'provider_name': providerName,
    'model_name': modelName,
    'duration_ms': durationMs,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
  };
}

bool _sameWarnings(List<ReviewWarningPayload> first, List<ReviewWarningPayload> second) =>
    first.length == second.length &&
    List.generate(first.length, (index) => first[index].signature() == second[index].signature())
        .every((matches) => matches);

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be an array.');
  return List<Object?>.from(value);
}

void _requireKeys(
  Map<String, Object?> value,
  Set<String> required,
  String label, {
  Set<String> optional = const {},
}) {
  final missing = required.difference(value.keys.toSet());
  if (missing.isNotEmpty) throw FormatException('$label is missing required fields.');
  final allowed = {...required, ...optional};
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('$label contains unsupported fields.');
  }
}

String _string(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a string.');
  return value;
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

String _boundedString(Object? value, String label, int minimum, int maximum) {
  final string = _string(value, label);
  if (string.length < minimum || string.length > maximum) {
    throw FormatException('$label has an invalid length.');
  }
  return string;
}

String? _optionalBoundedString(Object? value, String label, int maximum) =>
    value == null ? null : _boundedString(value, label, 0, maximum);

String _enumValue(Object? value, String label, List<String> choices) {
  final string = _string(value, label);
  if (!choices.contains(string)) throw FormatException('$label has an unsupported value.');
  return string;
}
