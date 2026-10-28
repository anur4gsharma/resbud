import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/import/document_project_extractor.dart';
import 'package:resbud_mobile/import/source_document_importer.dart';

void main() {
  group('DocumentProjectExtractor', () {
    const extractor = DocumentProjectExtractor();

    test('extracts research metadata from markdown with headers and sections', () {
      const sampleMarkdown = '''
# Neural Syndrome Decoding for Topological Quantum Codes

Field: Quantum Computing
Research Question: Can message-passing neural networks outperform minimum-weight perfect matching on correlated quantum error syndrome graphs?

## Objectives
- Train message-passing graph networks on topological error syndromes
- Benchmark decoding latency across distance 3, 5, and 7 surface codes
- Evaluate logical error rates under correlated multi-qubit Pauli noise

## Contribution
We demonstrate an equivariant graph neural network decoder that reduces logical error rates by 23% over MWPM while achieving sub-millisecond per-round decoding throughput on GPUs.

## Methodology
We simulate toric and planar surface codes using Stim, construct syndrome graphs with topological edge embeddings, and train graph neural networks using supervised loss against true Pauli error vectors.

## Results
The proposed decoder lowers logical error rate by 23% at code distance 5 and reduces decoding runtime from 4.2ms to 0.8ms per syndrome measurement round.

## Limitations
Current evaluation is restricted to simulated depolarizing and circuit-level Pauli noise; leakage and non-Markovian noise effects are left for future work.

## References
1. Fowler, A. G., et al. (2012). Surface codes: Towards practical large-scale quantum computation. Physical Review A, 86(3), 032324.
2. Dennis, E., et al. (2002). Topological quantum memory. Journal of Mathematical Physics, 43(9), 4452-4455.
''';

      final extracted = extractor.extract(
        fileName: 'quantum_paper_notes.md',
        rawText: sampleMarkdown,
      );

      expect(extracted.title, 'Neural Syndrome Decoding for Topological Quantum Codes');
      expect(extracted.researchField, 'Quantum Computing');
      expect(
        extracted.researchQuestion,
        'Can message-passing neural networks outperform minimum-weight perfect matching on correlated quantum error syndrome graphs?',
      );
      expect(extracted.objectives.length, 3);
      expect(
        extracted.objectives[0],
        'Train message-passing graph networks on topological error syndromes',
      );
      expect(extracted.claimedContribution, contains('23% over MWPM'));
      expect(extracted.methodologyStatus, 'provided');
      expect(extracted.methodology, contains('simulate toric and planar surface codes'));
      expect(extracted.resultsStatus, 'provided');
      expect(extracted.results, contains('lowers logical error rate by 23%'));
      expect(extracted.limitationsStatus, 'provided');
      expect(extracted.limitations, contains('depolarizing and circuit-level Pauli noise'));
      expect(extracted.references.length, 2);
      expect(extracted.references[0], contains('Fowler, A. G.'));
      expect(extracted.references[1], contains('Dennis, E.'));
      expect(extracted.sourceDraft, sampleMarkdown.trim());
    });

    test('extracts clean defaults when given raw unformatted notes', () {
      const plainText = '''
Quantum Graph States Analysis
We investigate how graph neural networks decode surface codes.
Our aim is to test decoding latency and accuracy.
''';

      final extracted = extractor.extract(
        fileName: 'notes.txt',
        rawText: plainText,
      );

      expect(extracted.title, 'Quantum Graph States Analysis');
      expect(extracted.researchField, isNotEmpty);
      expect(extracted.researchQuestion, isNotEmpty);
      expect(extracted.objectives, isNotEmpty);
      expect(extracted.claimedContribution, isNotEmpty);
      expect(extracted.sourceDraft, plainText.trim());
    });
  });

  group('SourceDocumentImporter markdown support', () {
    const importer = SourceDocumentImporter();

    test('imports .md files successfully', () {
      final bytes = Uint8List.fromList(utf8.encode('# Markdown Research Notes\nContent'));
      final result = importer.importBytes(fileName: 'research.md', bytes: bytes);
      expect(result.format, 'md');
      expect(result.text, '# Markdown Research Notes\nContent');
    });

    test('imports .markdown files successfully', () {
      final bytes = Uint8List.fromList(utf8.encode('Notes from experiment'));
      final result = importer.importBytes(fileName: 'notes.markdown', bytes: bytes);
      expect(result.format, 'markdown');
      expect(result.text, 'Notes from experiment');
    });
  });
}
