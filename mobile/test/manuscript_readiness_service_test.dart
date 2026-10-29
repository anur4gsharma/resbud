import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/readiness/manuscript_readiness_service.dart';

void main() {
  const service = ManuscriptReadinessService();

  PaperDraftPayload createDraft({
    String title = 'Sample Title',
    String abstractText = 'This paper presents a formal analysis of distributed consensus mechanisms under adversarial partitions.',
    List<PaperSectionPayload>? sections,
    List<ReferencePayload>? references,
    List<ReviewWarningPayload>? reviewWarnings,
  }) {
    return PaperDraftPayload(
      schemaVersion: 1,
      title: title,
      abstractText: abstractText,
      keywords: const ['consensus', 'distributed systems'],
      sections: sections ??
          [
            const PaperSectionPayload(
              id: 'intro',
              heading: 'Introduction',
              content: 'Distributed systems require fault-tolerant agreement.',
              state: 'draft',
            ),
            const PaperSectionPayload(
              id: 'method',
              heading: 'Methodology and Formal Proofs',
              content: 'We model the network as an asynchronous message-passing system.',
              state: 'draft',
            ),
            const PaperSectionPayload(
              id: 'results',
              heading: 'Evaluation and Results',
              content: 'The protocol achieves zero-latency commit in benign network states.',
              state: 'draft',
            ),
          ],
      references: references ??
          [
            const ReferencePayload(
              id: 'lamport1982',
              text: 'Lamport, L., Shostak, R., & Pease, M. (1982). The Byzantine Generals Problem.',
            ),
          ],
      reviewWarnings: reviewWarnings ?? const [],
    );
  }

  group('ManuscriptReadinessService - Critical Missing Information', () {
    test('flags missing or whitespace-only title as critical', () {
      final draft = createDraft(title: '   ');
      final report = service.evaluate(paper: draft);

      final titleFindings = report.criticalFindings.where((f) => f.code == 'EMPTY_TITLE');
      expect(titleFindings, hasLength(1));
      expect(titleFindings.first.category, ReadinessCategory.criticalMissing);
      expect(titleFindings.first.severity, ReadinessSeverity.critical);
    });

    test('flags missing abstract as critical and short abstract as warning', () {
      final emptyAbstract = createDraft(abstractText: '');
      final reportEmpty = service.evaluate(paper: emptyAbstract);
      expect(reportEmpty.criticalFindings.where((f) => f.code == 'EMPTY_ABSTRACT'), hasLength(1));

      final shortAbstract = createDraft(abstractText: 'Too short abstract.');
      final reportShort = service.evaluate(paper: shortAbstract);
      expect(reportShort.warningFindings.where((f) => f.code == 'SHORT_ABSTRACT'), hasLength(1));
    });

    test('flags blank section content with specific section association', () {
      final draft = createDraft(
        sections: [
          const PaperSectionPayload(
            id: 'blank_sec',
            heading: 'System Architecture',
            content: '   \n  ',
            state: 'draft',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      final blankFinding = report.criticalFindings.firstWhere((f) => f.code == 'BLANK_SECTION');
      expect(blankFinding.sectionId, 'blank_sec');
      expect(blankFinding.sectionHeading, 'System Architecture');
      expect(blankFinding.suggestedAction, isNotNull);
    });
  });

  group('ManuscriptReadinessService - Research Completeness', () {
    test('maps generation review warnings into structured completeness findings', () {
      final draft = createDraft(
        reviewWarnings: const [
          ReviewWarningPayload(
            code: 'MISSING_LIMITATIONS',
            severity: 'warning',
            message: 'No threats to validity or limitations were specified.',
            sectionId: 'results',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      final finding = report.findings.firstWhere((f) => f.code == 'MISSING_LIMITATIONS');
      expect(finding.category, ReadinessCategory.researchCompleteness);
      expect(finding.severity, ReadinessSeverity.warning);
      expect(finding.sectionId, 'results');
      expect(finding.explanation, contains('limitations'));
    });

    test('flags missing methodology and missing results when absent from headings', () {
      final draft = createDraft(
        sections: [
          const PaperSectionPayload(
            id: 'background',
            heading: 'Historical Background',
            content: 'Historical overview of classical protocols.',
            state: 'draft',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      expect(report.findings.any((f) => f.code == 'MISSING_METHOD'), isTrue);
      expect(report.findings.any((f) => f.code == 'MISSING_RESULTS'), isTrue);
    });
  });

  group('ManuscriptReadinessService - Citations and References', () {
    test('flags unsupplied references when references list is empty', () {
      final draft = createDraft(references: const []);
      final report = service.evaluate(paper: draft);

      final refFinding = report.warningFindings.firstWhere((f) => f.code == 'NO_REFERENCES_SUPPLIED');
      expect(refFinding.category, ReadinessCategory.citationAndReferences);
    });

    test('flags incomplete reference text under 10 characters', () {
      final draft = createDraft(
        references: [
          const ReferencePayload(id: 'r1', text: 'arXiv'),
        ],
      );
      final report = service.evaluate(paper: draft);

      expect(report.warningFindings.any((f) => f.code == 'REFERENCE_INCOMPLETE'), isTrue);
    });

    test('flags inline [citation needed] tags in section content', () {
      final draft = createDraft(
        sections: [
          const PaperSectionPayload(
            id: 'claims',
            heading: 'Key Assertions',
            content: 'The new approach reduces communication rounds by 40% [citation needed].',
            state: 'draft',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      final finding = report.warningFindings.firstWhere((f) => f.code == 'CITATION_NEEDED');
      expect(finding.sectionId, 'claims');
      expect(finding.category, ReadinessCategory.citationAndReferences);
    });
  });

  group('ManuscriptReadinessService - Editorial Review', () {
    test('flags placeholder snippets like [TODO: insert details] or lorem ipsum', () {
      final draft = createDraft(
        sections: [
          const PaperSectionPayload(
            id: 'sec1',
            heading: 'Protocol Specification',
            content: 'We define the algorithm below. [TODO: add formal pseudocode].',
            state: 'draft',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      final placeholderFinding = report.warningFindings.firstWhere((f) => f.code == 'PLACEHOLDER_TEXT');
      expect(placeholderFinding.sectionId, 'sec1');
      expect(placeholderFinding.category, ReadinessCategory.editorialReview);
    });

    test('flags duplicate section headings', () {
      final draft = createDraft(
        sections: [
          const PaperSectionPayload(
            id: 's1',
            heading: 'Evaluation',
            content: 'First evaluation batch.',
            state: 'draft',
          ),
          const PaperSectionPayload(
            id: 's2',
            heading: 'evaluation',
            content: 'Second evaluation batch.',
            state: 'draft',
          ),
        ],
      );
      final report = service.evaluate(paper: draft);

      expect(report.findings.any((f) => f.code == 'DUPLICATE_HEADING'), isTrue);
    });
  });

  group('ManuscriptReadinessService - Structural Completeness Metric', () {
    test('computes deterministic percentage of core structural items', () {
      final completeDraft = createDraft();
      final completeReport = service.evaluate(paper: completeDraft);
      expect(completeReport.structuralChecklistPercentage, 100);
      expect(completeReport.completedStructuralItems, 6);
      expect(completeReport.totalStructuralItems, 6);

      final minimalDraft = createDraft(
        title: '',
        abstractText: '',
        sections: [],
        references: [],
      );
      final minimalReport = service.evaluate(paper: minimalDraft);
      expect(minimalReport.structuralChecklistPercentage, 0);
      expect(minimalReport.completedStructuralItems, 0);
    });
  });
}
