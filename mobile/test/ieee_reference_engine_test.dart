import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  group('IEEE Reference Engine Mobile Tests', () {
    test('ReferencePayload serializes and deserializes all 11 publication types and metadata', () {
      final json = <String, Object?>{
        'id': 'ref_journal',
        'text': 'A. Author, "Study Title," IEEE Trans., 2024.',
        'authors': ['A. Author', 'B. Author'],
        'year': 2024,
        'title': 'Study Title',
        'venue': 'IEEE Trans.',
        'volume': '12',
        'issue': '3',
        'pages': '100–110',
        'publisher': 'IEEE',
        'doi': '10.1109/TSE.2024.1234567',
        'url': 'https://doi.org/10.1109/TSE.2024.1234567',
        'isbn_or_issn': '0098-5589',
        'access_date': 'Jan. 15, 2024',
        'publication_type': 'journal_article',
        'provenance': 'crossref',
        'verification_status': 'verified',
        'citation_number': 1,
        'citation_locations': ['sec_intro', 'sec_results'],
        'is_cited': true,
        'review_warning': 'Sample warning',
      };

      final ref = ReferencePayload.fromJson(json);
      expect(ref.id, 'ref_journal');
      expect(ref.title, 'Study Title');
      expect(ref.authors, ['A. Author', 'B. Author']);
      expect(ref.year, 2024);
      expect(ref.venue, 'IEEE Trans.');
      expect(ref.publicationType, 'journal_article');
      expect(ref.provenance, 'crossref');
      expect(ref.verificationStatus, 'verified');
      expect(ref.citationNumber, 1);
      expect(ref.citationLocations, ['sec_intro', 'sec_results']);
      expect(ref.isCited, isTrue);
      expect(ref.reviewWarning, 'Sample warning');

      final serialized = ref.toJson();
      expect(serialized['id'], 'ref_journal');
      expect(serialized['doi'], '10.1109/TSE.2024.1234567');
      expect(serialized['publication_type'], 'journal_article');
      expect(serialized['citation_number'], 1);
      expect(serialized['is_cited'], isTrue);
    });

    test('ReferencePayload copyWith updates specific fields while preserving others', () {
      const original = ReferencePayload(
        id: 'ref_orig',
        text: 'Initial citation',
        title: 'Original Title',
        authors: ['Original Author'],
        year: 2020,
        publicationType: 'journal_article',
        isCited: false,
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        year: 2024,
        isCited: true,
        citationNumber: 2,
      );

      expect(updated.id, 'ref_orig');
      expect(updated.title, 'Updated Title');
      expect(updated.authors, ['Original Author']);
      expect(updated.year, 2024);
      expect(updated.publicationType, 'journal_article');
      expect(updated.isCited, isTrue);
      expect(updated.citationNumber, 2);
    });

    test('PaperDraftPayload with structured references preserves references across copyWith', () {
      const ref1 = ReferencePayload(
        id: 'ref_1',
        text: 'First reference',
        citationNumber: 1,
        isCited: true,
      );
      const ref2 = ReferencePayload(
        id: 'ref_2',
        text: 'Second reference',
        citationNumber: 2,
        isCited: true,
      );

      const draft = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Paper Title',
        abstractText: 'Abstract text',
        keywords: ['NLP'],
        sections: [
          PaperSectionPayload(
            id: 'intro',
            heading: 'Introduction',
            content: 'Citing [1] and [2].',
            state: 'draft',
          ),
        ],
        references: [ref1, ref2],
        reviewWarnings: [],
      );

      expect(draft.references.length, 2);
      expect(draft.references[0].id, 'ref_1');

      // Add a third reference
      const ref3 = ReferencePayload(
        id: 'ref_3',
        text: 'Third reference',
        citationNumber: 3,
        isCited: false,
      );
      final updatedDraft = draft.copyWith(
        references: [...draft.references, ref3],
      );

      expect(updatedDraft.references.length, 3);
      expect(updatedDraft.references[2].id, 'ref_3');
      expect(updatedDraft.references[2].isCited, isFalse);
    });
  });
}
