import 'package:flutter/foundation.dart';
import '../generation/generation_models.dart';

/// Severity level for readiness findings.
enum ReadinessSeverity {
  critical,
  warning,
  info,
}

/// Category of manuscript readiness issue.
enum ReadinessCategory {
  criticalMissing,
  researchCompleteness,
  citationAndReferences,
  editorialReview,
}

/// A structured finding identified during deterministic manuscript inspection.
@immutable
class ReadinessFinding {
  const ReadinessFinding({
    required this.id,
    required this.category,
    required this.severity,
    required this.code,
    required this.title,
    required this.explanation,
    this.sectionId,
    this.sectionHeading,
    this.suggestedAction,
  });

  final String id;
  final ReadinessCategory category;
  final ReadinessSeverity severity;
  final String code;
  final String title;
  final String explanation;
  final String? sectionId;
  final String? sectionHeading;
  final String? suggestedAction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadinessFinding &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code &&
          sectionId == other.sectionId;

  @override
  int get hashCode => Object.hash(id, code, sectionId);
}

/// Deterministic summary report of manuscript readiness.
@immutable
class ReadinessReport {
  const ReadinessReport({
    required this.findings,
    required this.evaluatedAt,
    required this.sectionsCount,
    required this.totalWords,
    required this.referencesCount,
    required this.completedStructuralItems,
    required this.totalStructuralItems,
  });

  final List<ReadinessFinding> findings;
  final DateTime evaluatedAt;
  final int sectionsCount;
  final int totalWords;
  final int referencesCount;
  final int completedStructuralItems;
  final int totalStructuralItems;

  /// Deterministic structural presence percentage.
  /// Strictly measures structural presence of core manuscript elements,
  /// NOT scientific correctness, peer-review acceptance, or factual truth.
  int get structuralChecklistPercentage {
    if (totalStructuralItems == 0) return 100;
    return ((completedStructuralItems / totalStructuralItems) * 100).round().clamp(0, 100);
  }

  List<ReadinessFinding> get criticalFindings =>
      findings.where((f) => f.severity == ReadinessSeverity.critical).toList(growable: false);

  List<ReadinessFinding> get warningFindings =>
      findings.where((f) => f.severity == ReadinessSeverity.warning).toList(growable: false);

  List<ReadinessFinding> get infoFindings =>
      findings.where((f) => f.severity == ReadinessSeverity.info).toList(growable: false);

  List<ReadinessFinding> byCategory(ReadinessCategory category) =>
      findings.where((f) => f.category == category).toList(growable: false);

  bool get hasCriticalIssues => criticalFindings.isNotEmpty;
  bool get hasIssues => findings.isNotEmpty;
}

/// Deterministic, offline inspection service evaluating manuscript readiness.
///
/// Research Integrity Guarantee:
/// This service performs deterministic structural, citation, and warning analysis only.
/// It NEVER claims to verify scientific correctness, empirical validity, or publication readiness.
class ManuscriptReadinessService {
  const ManuscriptReadinessService();

  static final RegExp _placeholderRegex = RegExp(
    r'(\[TODO[^\]]*\]|\[Insert[^\]]*\]|\[TBD[^\]]*\]|\[Draft[^\]]*\]|\[citation needed\]|\[ref\?\]|lorem ipsum)',
    caseSensitive: false,
  );

  static final RegExp _citationNeededRegex = RegExp(
    r'(\[citation needed\]|\[citation required\]|\[TODO:\s*cite\]|\[ref\?\])',
    caseSensitive: false,
  );

  /// Evaluate the provided [paper] and optional [projectContext] into a structured [ReadinessReport].
  ReadinessReport evaluate({
    required PaperDraftPayload paper,
    Map<String, Object?>? projectContext,
  }) {
    final findings = <ReadinessFinding>[];
    int findingCounter = 0;

    String nextId() => 'finding_${++findingCounter}';

    // -------------------------------------------------------------
    // 1. Critical Missing Information
    // -------------------------------------------------------------
    final titleTrimmed = paper.title.trim();
    if (titleTrimmed.isEmpty || titleTrimmed.toLowerCase() == 'untitled paper') {
      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: ReadinessCategory.criticalMissing,
          severity: ReadinessSeverity.critical,
          code: 'EMPTY_TITLE',
          title: 'Working title is missing',
          explanation: 'The manuscript has no substantive title defined.',
          suggestedAction: 'Supply a descriptive academic title in the manuscript header.',
        ),
      );
    }

    final abstractTrimmed = paper.abstractText.trim();
    if (abstractTrimmed.isEmpty) {
      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: ReadinessCategory.criticalMissing,
          severity: ReadinessSeverity.critical,
          code: 'EMPTY_ABSTRACT',
          title: 'Abstract is missing',
          explanation: 'The paper draft does not contain an abstract summary.',
          suggestedAction: 'Write or generate a concise abstract outlining objectives, methodology, and findings.',
        ),
      );
    } else if (abstractTrimmed.split(RegExp(r'\s+')).length < 20) {
      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: ReadinessCategory.criticalMissing,
          severity: ReadinessSeverity.warning,
          code: 'SHORT_ABSTRACT',
          title: 'Abstract is very brief',
          explanation: 'The abstract is fewer than 20 words and may not sufficiently summarize the manuscript.',
          suggestedAction: 'Expand the abstract to clearly state the research question, approach, and findings.',
        ),
      );
    }

    if (paper.sections.isEmpty) {
      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: ReadinessCategory.criticalMissing,
          severity: ReadinessSeverity.critical,
          code: 'NO_SECTIONS',
          title: 'No sections in manuscript',
          explanation: 'The manuscript contains zero body sections.',
          suggestedAction: 'Add at least one manuscript section or regenerate the draft.',
        ),
      );
    }

    // Check each section for blank content
    for (final section in paper.sections) {
      final contentTrimmed = section.content.trim();
      if (contentTrimmed.isEmpty) {
        findings.add(
          ReadinessFinding(
            id: nextId(),
            category: ReadinessCategory.criticalMissing,
            severity: ReadinessSeverity.critical,
            code: 'BLANK_SECTION',
            title: 'Section "${section.heading}" is blank',
            explanation: 'The section "${section.heading}" has no draft content.',
            sectionId: section.id,
            sectionHeading: section.heading,
            suggestedAction: 'Write draft content for this section or regenerate it with AI.',
          ),
        );
      }
    }

    // -------------------------------------------------------------
    // 2. Research Completeness
    // -------------------------------------------------------------
    // Inspect paper's review_warnings produced during generation
    for (final warning in paper.reviewWarnings) {
      final category = _mapWarningCodeToCategory(warning.code);
      final severity = _mapWarningSeverity(warning.severity);

      final matchingSection = warning.sectionId != null
          ? paper.sections.where((s) => s.id == warning.sectionId).firstOrNull
          : null;

      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: category,
          severity: severity,
          code: warning.code,
          title: _warningCodeTitle(warning.code, matchingSection?.heading),
          explanation: warning.message,
          sectionId: warning.sectionId,
          sectionHeading: matchingSection?.heading,
          suggestedAction: _warningCodeSuggestedAction(warning.code),
        ),
      );
    }

    // Check for methodology & results presence
    final headingsLower = paper.sections.map((s) => s.heading.toLowerCase()).toList(growable: false);
    final hasMethodology = headingsLower.any((h) => h.contains('method') || h.contains('approach') || h.contains('design'));
    final hasResults = headingsLower.any((h) => h.contains('result') || h.contains('evaluation') || h.contains('experiment') || h.contains('finding'));

    if (paper.sections.isNotEmpty && !hasMethodology) {
      final alreadyFlagged = findings.any((f) => f.code == 'MISSING_METHOD');
      if (!alreadyFlagged) {
        findings.add(
          ReadinessFinding(
            id: nextId(),
            category: ReadinessCategory.researchCompleteness,
            severity: ReadinessSeverity.warning,
            code: 'MISSING_METHOD',
            title: 'No methodology section detected',
            explanation: 'Standard academic manuscripts describe procedures, experimental design, or analytical methods.',
            suggestedAction: 'Include a Methodology or Research Design section explaining your approach.',
          ),
        );
      }
    }

    if (paper.sections.isNotEmpty && !hasResults) {
      final alreadyFlagged = findings.any((f) => f.code == 'MISSING_RESULTS');
      if (!alreadyFlagged) {
        findings.add(
          ReadinessFinding(
            id: nextId(),
            category: ReadinessCategory.researchCompleteness,
            severity: ReadinessSeverity.info,
            code: 'MISSING_RESULTS',
            title: 'No experimental results section detected',
            explanation: 'No section heading indicates empirical results, evaluation, or experimental outcomes.',
            suggestedAction: 'Ensure experimental findings are recorded, or mark results as explicitly unperformed.',
          ),
        );
      }
    }

    // -------------------------------------------------------------
    // 3. Citation and Reference Review
    // -------------------------------------------------------------
    if (paper.references.isEmpty) {
      findings.add(
        ReadinessFinding(
          id: nextId(),
          category: ReadinessCategory.citationAndReferences,
          severity: ReadinessSeverity.warning,
          code: 'NO_REFERENCES_SUPPLIED',
          title: 'Zero references supplied',
          explanation: 'The manuscript has no supplied bibliographic references. Grounding cannot be independently verified.',
          suggestedAction: 'Supply authoritative references in the project input to anchor manuscript citations.',
        ),
      );
    } else {
      for (final ref in paper.references) {
        final refTextTrimmed = ref.text.trim();
        if (refTextTrimmed.length < 10) {
          findings.add(
            ReadinessFinding(
              id: nextId(),
              category: ReadinessCategory.citationAndReferences,
              severity: ReadinessSeverity.warning,
              code: 'REFERENCE_INCOMPLETE',
              title: 'Incomplete reference entry',
              explanation: 'Reference [${ref.id}] is unusually brief: "$refTextTrimmed".',
              suggestedAction: 'Provide full bibliographic details (authors, year, title, venue) for [${ref.id}].',
            ),
          );
        }
      }
    }

    // Check for inline [citation needed] tags
    for (final section in paper.sections) {
      if (_citationNeededRegex.hasMatch(section.content)) {
        final alreadyFlagged = findings.any(
          (f) => f.sectionId == section.id && f.code == 'CITATION_NEEDED',
        );
        if (!alreadyFlagged) {
          findings.add(
            ReadinessFinding(
              id: nextId(),
              category: ReadinessCategory.citationAndReferences,
              severity: ReadinessSeverity.warning,
              code: 'CITATION_NEEDED',
              title: 'Citation placeholder in "${section.heading}"',
              explanation: 'Section contains explicit [citation needed] or [ref?] markers that require researcher confirmation.',
              sectionId: section.id,
              sectionHeading: section.heading,
              suggestedAction: 'Link claim to an authoritative reference or remove unsupported assertions.',
            ),
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 4. Editorial Review
    // -------------------------------------------------------------
    // Check for placeholder text across all sections
    for (final section in paper.sections) {
      final matches = _placeholderRegex.allMatches(section.content);
      for (final match in matches) {
        final snippet = match.group(0) ?? '';
        if (_citationNeededRegex.hasMatch(snippet)) continue; // Handled under citation review
        findings.add(
          ReadinessFinding(
            id: nextId(),
            category: ReadinessCategory.editorialReview,
            severity: ReadinessSeverity.warning,
            code: 'PLACEHOLDER_TEXT',
            title: 'Placeholder text in "${section.heading}"',
            explanation: 'Detected editorial placeholder snippet "$snippet" in section content.',
            sectionId: section.id,
            sectionHeading: section.heading,
            suggestedAction: 'Replace placeholder with actual research description or remove it.',
          ),
        );
        break; // Flag once per section to avoid noise
      }
    }

    // Check for duplicate headings
    final seenHeadings = <String, String>{};
    for (final section in paper.sections) {
      final norm = section.heading.trim().toLowerCase();
      if (seenHeadings.containsKey(norm)) {
        findings.add(
          ReadinessFinding(
            id: nextId(),
            category: ReadinessCategory.editorialReview,
            severity: ReadinessSeverity.info,
            code: 'DUPLICATE_HEADING',
            title: 'Duplicate section heading: "${section.heading}"',
            explanation: 'Multiple sections share the identical heading "${section.heading}".',
            sectionId: section.id,
            sectionHeading: section.heading,
            suggestedAction: 'Differentiate subsection titles to preserve a clear document hierarchy.',
          ),
        );
      } else {
        seenHeadings[norm] = section.id;
      }
    }

    // Compute structural checklist presence:
    // Core items: Title, Abstract, Intro/Background, Method, Results/Discussion, References
    int completedCore = 0;
    const totalCore = 6;
    if (titleTrimmed.isNotEmpty && titleTrimmed.toLowerCase() != 'untitled paper') completedCore++;
    if (abstractTrimmed.isNotEmpty && abstractTrimmed.split(RegExp(r'\s+')).length >= 10) completedCore++;
    if (headingsLower.any((h) => h.contains('intro') || h.contains('background') || h.contains('overview'))) completedCore++;
    if (hasMethodology) completedCore++;
    if (hasResults || headingsLower.any((h) => h.contains('discussion') || h.contains('conclusion'))) completedCore++;
    if (paper.references.isNotEmpty) completedCore++;

    int totalWords = 0;
    if (abstractTrimmed.isNotEmpty) {
      totalWords += abstractTrimmed.split(RegExp(r'\s+')).length;
    }
    for (final section in paper.sections) {
      final words = section.content.trim().split(RegExp(r'\s+'));
      if (words.length == 1 && words[0].isEmpty) continue;
      totalWords += words.length;
    }

    return ReadinessReport(
      findings: List.unmodifiable(findings),
      evaluatedAt: DateTime.now(),
      sectionsCount: paper.sections.length,
      totalWords: totalWords,
      referencesCount: paper.references.length,
      completedStructuralItems: completedCore,
      totalStructuralItems: totalCore,
    );
  }

  ReadinessCategory _mapWarningCodeToCategory(String code) {
    switch (code) {
      case 'MISSING_METHOD':
      case 'MISSING_DATASET_DETAILS':
      case 'MISSING_RESULTS':
      case 'MISSING_LIMITATIONS':
      case 'SECTION_NOT_APPLICABLE':
      case 'INPUT_CONFLICT':
        return ReadinessCategory.researchCompleteness;
      case 'CITATION_NEEDED':
      case 'REFERENCE_INCOMPLETE':
      case 'CLAIM_NEEDS_REVIEW':
        return ReadinessCategory.citationAndReferences;
      case 'GENERAL_REVIEW':
      default:
        return ReadinessCategory.editorialReview;
    }
  }

  ReadinessSeverity _mapWarningSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return ReadinessSeverity.critical;
      case 'warning':
        return ReadinessSeverity.warning;
      case 'info':
      default:
        return ReadinessSeverity.info;
    }
  }

  String _warningCodeTitle(String code, String? sectionHeading) {
    final prefix = sectionHeading != null ? 'In "$sectionHeading": ' : '';
    switch (code) {
      case 'MISSING_METHOD':
        return '${prefix}Missing methodology details';
      case 'MISSING_DATASET_DETAILS':
        return '${prefix}Missing dataset/materials description';
      case 'MISSING_RESULTS':
        return '${prefix}Experimental results omitted or unconducted';
      case 'MISSING_LIMITATIONS':
        return '${prefix}Limitations not stated';
      case 'CITATION_NEEDED':
        return '${prefix}Claim requires citation';
      case 'REFERENCE_INCOMPLETE':
        return '${prefix}Incomplete reference';
      case 'CLAIM_NEEDS_REVIEW':
        return '${prefix}Claim requires researcher verification';
      case 'INPUT_CONFLICT':
        return '${prefix}Conflicting project input details';
      case 'SECTION_NOT_APPLICABLE':
        return '${prefix}Section marked not applicable';
      case 'GENERAL_REVIEW':
      default:
        return '${prefix}Review note';
    }
  }

  String _warningCodeSuggestedAction(String code) {
    switch (code) {
      case 'MISSING_METHOD':
        return 'State exact protocols, algorithms, or statistical techniques used.';
      case 'MISSING_DATASET_DETAILS':
        return 'Specify data sources, sample sizes, and preprocessing parameters.';
      case 'MISSING_RESULTS':
        return 'Supply measured outcomes or note explicitly that experiments are pending.';
      case 'MISSING_LIMITATIONS':
        return 'Explicitly state threats to validity, constraints, and scope boundaries.';
      case 'CITATION_NEEDED':
        return 'Provide peer-reviewed literature citations supporting the statement.';
      case 'REFERENCE_INCOMPLETE':
        return 'Verify DOI, publication venue, volume, and publication year.';
      case 'CLAIM_NEEDS_REVIEW':
        return 'Review factual accuracy against your lab notes or raw dataset.';
      case 'INPUT_CONFLICT':
        return 'Reconcile contradictory statements between the brief and draft.';
      case 'SECTION_NOT_APPLICABLE':
        return 'Confirm whether this section is intentionally omitted.';
      default:
        return 'Inspect the draft text and verify academic alignment.';
    }
  }
}
