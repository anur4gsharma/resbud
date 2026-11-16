import 'package:flutter/foundation.dart';

import '../../data/local_project_repository.dart';
import '../../data/project_figure.dart';
import '../generation/generation_models.dart';

/// Resolves figure identifiers (e.g. `(fig_1)`, `(fig_2)`) in manuscript section markdown
/// to embedded base64 data URIs with placement metadata before exporting to PDF or DOCX.
Future<PaperDraftPayload> resolveFiguresForExport({
  required PaperDraftPayload paper,
  required LocalProjectRepository repository,
  required String projectId,
}) async {
  try {
    final figures = await repository.listProjectFigures(projectId);
    if (figures.isEmpty) {
      return paper;
    }

    final updatedSections = await Future.wait(
      paper.sections.map((section) async {
        var content = section.content;
        for (final fig in figures) {
          final candidateMarkers = [
            fig.id,
            'fig_${fig.figureNumber}',
            'figure_${fig.figureNumber}',
            'figure${fig.figureNumber}',
          ];
          for (final marker in candidateMarkers) {
            if (content.contains('($marker)')) {
              final bytes = fig.cachedBytes ?? await repository.getFigureBytes(fig.storageKey);
              if (bytes != null && bytes.isNotEmpty) {
                final dataUri =
                    '${ProjectFigure.formatDataUri(fig.mimeType, bytes)}#placement=${fig.placement.value}';
                content = content.replaceAll('($marker)', '($dataUri)');
              }
            }
          }
        }
        return section.copyWith(content: content);
      }),
    );

    return paper.copyWith(sections: updatedSections);
  } catch (e) {
    debugPrint('Error resolving figures for export: $e');
    return paper;
  }
}
