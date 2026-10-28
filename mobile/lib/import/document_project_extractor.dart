class ExtractedProjectData {
  const ExtractedProjectData({
    required this.title,
    required this.researchField,
    required this.researchQuestion,
    required this.objectives,
    required this.claimedContribution,
    this.methodologyStatus = 'provided',
    this.methodology,
    this.datasetStatus = 'not_available',
    this.dataset,
    this.resultsStatus = 'provided',
    this.results,
    this.limitationsStatus = 'not_identified',
    this.limitations,
    required this.sourceDraft,
    this.references = const [],
  });

  final String title;
  final String researchField;
  final String researchQuestion;
  final List<String> objectives;
  final String claimedContribution;
  final String methodologyStatus;
  final String? methodology;
  final String datasetStatus;
  final String? dataset;
  final String resultsStatus;
  final String? results;
  final String limitationsStatus;
  final String? limitations;
  final String sourceDraft;
  final List<String> references;
}

class DocumentProjectExtractor {
  const DocumentProjectExtractor();

  ExtractedProjectData extract({
    required String fileName,
    required String rawText,
  }) {
    final cleaned = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final lines = cleaned.split('\n');

    // 1. Extract Title
    String? title;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        title = trimmed.substring(2).trim();
        break;
      }
    }
    if (title == null || title.isEmpty) {
      // Look for first non-empty line that isn't a markdown header or bullet
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith('#') &&
            !trimmed.startsWith('-') &&
            !trimmed.startsWith('*') &&
            trimmed.length <= 150) {
          title = trimmed;
          break;
        }
      }
    }
    if (title == null || title.isEmpty) {
      // Derive from file name
      final base = fileName.split(RegExp(r'[/\\]')).last;
      final dot = base.lastIndexOf('.');
      final nameWithoutExt = dot > 0 ? base.substring(0, dot) : base;
      title = nameWithoutExt
          .replaceAll(RegExp(r'[-_]'), ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    if (title.isEmpty) {
      title = 'Scientific Research Study';
    }

    // 2. Parse Markdown / Label Sections
    final sections = _parseSections(cleaned);

    // 3. Research Field
    var field = _findSection(sections, ['field', 'research field', 'domain', 'area', 'discipline']);
    if (field == null || field.isEmpty) {
      field = _inferFieldFromContent('$title\n$cleaned');
    }

    // 4. Research Question / Problem Statement
    var question = _findSection(sections, [
      'problem statement',
      'research question',
      'problem',
      'motivation',
      'introduction',
      'background',
    ]);
    if (question == null || question.isEmpty) {
      // Find first substantial paragraph
      final paragraphs = cleaned
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty && !p.startsWith('#'))
          .toList();
      question = paragraphs.isNotEmpty
          ? paragraphs.first
          : 'What are the primary theoretical constraints and empirical performance properties of $title?';
    }

    // 5. Objectives
    final objectives = <String>[];
    final objectivesText = _findSection(sections, [
      'objectives',
      'goals',
      'aims',
      'project objectives',
      'research goals',
    ]);
    if (objectivesText != null && objectivesText.isNotEmpty) {
      for (final line in objectivesText.split('\n')) {
        final trimmed = line.replaceFirst(RegExp(r'^\s*[-*•\d\.)]+\s*'), '').trim();
        if (trimmed.isNotEmpty) {
          objectives.add(trimmed);
        }
      }
    }
    // If no explicit section, look for any bullet points in document
    if (objectives.isEmpty) {
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
          final item = trimmed.replaceFirst(RegExp(r'^\s*[-*•\d\.)]+\s*'), '').trim();
          if (item.length > 5 && item.length < 500) {
            objectives.add(item);
            if (objectives.length >= 5) break;
          }
        }
      }
    }
    // Fallback objectives if still empty
    if (objectives.isEmpty) {
      objectives.add('Investigate fundamental theoretical foundations and operational constraints of $title.');
      objectives.add('Formulate and implement the proposed methodological architecture.');
      objectives.add('Conduct systematic empirical benchmarking against baseline models.');
    }

    // 6. Claimed Contribution
    var contribution = _findSection(sections, [
      'contribution',
      'contributions',
      'claimed contribution',
      'key contributions',
    ]);
    if (contribution == null || contribution.isEmpty) {
      contribution = 'A comprehensive methodological framework and empirical evaluation establishing validated performance advances in $title.';
    }

    // 7. Methodology
    final methodology = _findSection(sections, [
      'methodology',
      'method',
      'methods',
      'approach',
      'system architecture',
      'experimental setup',
    ]);

    // 8. Results
    final results = _findSection(sections, [
      'results',
      'findings',
      'evaluation',
      'experiments',
      'empirical results',
      'performance',
    ]);

    // 9. Limitations
    final limitations = _findSection(sections, [
      'limitations',
      'threats to validity',
      'limitations and future work',
    ]);

    // 10. References
    final references = <String>[];
    final referencesText = _findSection(sections, [
      'references',
      'bibliography',
      'works cited',
      'citations',
    ]);
    if (referencesText != null && referencesText.isNotEmpty) {
      for (final line in referencesText.split('\n')) {
        final trimmed = line.replaceFirst(RegExp(r'^\s*[-*•\d\.)\[\]]+\s*'), '').trim();
        if (trimmed.length > 5) {
          references.add(trimmed);
        }
      }
    }

    return ExtractedProjectData(
      title: title,
      researchField: field,
      researchQuestion: question,
      objectives: objectives,
      claimedContribution: contribution,
      methodologyStatus: (methodology != null && methodology.isNotEmpty) ? 'provided' : 'not_available',
      methodology: methodology,
      resultsStatus: (results != null && results.isNotEmpty) ? 'provided' : 'not_collected',
      results: results,
      limitationsStatus: (limitations != null && limitations.isNotEmpty) ? 'provided' : 'not_identified',
      limitations: limitations,
      sourceDraft: cleaned,
      references: references,
    );
  }

  Map<String, String> _parseSections(String text) {
    final sections = <String, String>{};
    final lines = text.split('\n');
    String? currentHeading;
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentHeading != null) buffer.writeln();
        continue;
      }

      // Check for inline Key: Value (e.g. Field: Quantum Computing, Research Question: ...)
      final kvMatch = RegExp(r'^([A-Za-z\s]{2,30}):\s+(.+)$').firstMatch(trimmed);
      if (kvMatch != null &&
          !trimmed.startsWith('#') &&
          !trimmed.startsWith('-') &&
          !trimmed.startsWith('*')) {
        final key = kvMatch.group(1)!.trim().toLowerCase();
        final val = kvMatch.group(2)!.trim();
        sections[key] = val;
        continue;
      }

      // Check for markdown headers (# ... ####) or standalone headers (Header:)
      final isHeader = trimmed.startsWith('#') ||
          RegExp(r'^[A-Z][A-Za-z\s]{2,30}:\s*$').hasMatch(trimmed);

      if (isHeader) {
        if (currentHeading != null && buffer.isNotEmpty) {
          sections[currentHeading] = buffer.toString().trim();
          buffer.clear();
        }
        var h = trimmed.replaceAll(RegExp(r'^#+\s*'), '').trim();
        if (h.endsWith(':')) {
          h = h.substring(0, h.length - 1).trim();
        }
        currentHeading = h.toLowerCase();
      } else if (currentHeading != null) {
        buffer.writeln(line);
      }
    }

    if (currentHeading != null && buffer.isNotEmpty) {
      sections[currentHeading] = buffer.toString().trim();
    }

    return sections;
  }

  String? _findSection(Map<String, String> sections, List<String> candidates) {
    for (final candidate in candidates) {
      final lower = candidate.toLowerCase();
      if (sections.containsKey(lower)) {
        final val = sections[lower]!.trim();
        if (val.isNotEmpty) return val;
      }
      for (final entry in sections.entries) {
        if (entry.key.contains(lower) || lower.contains(entry.key)) {
          final val = entry.value.trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
    return null;
  }

  String _inferFieldFromContent(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('quantum')) return 'Quantum Information & Physics';
    if (lower.contains('neural') || lower.contains('deep learning') || lower.contains('llm') || lower.contains('transformer') || lower.contains('ai')) {
      return 'Computer Science / Artificial Intelligence';
    }
    if (lower.contains('network') || lower.contains('distributed') || lower.contains('cloud') || lower.contains('database')) {
      return 'Computer Systems & Networking';
    }
    if (lower.contains('biology') || lower.contains('gene') || lower.contains('protein') || lower.contains('medical')) {
      return 'Computational Biology & Medicine';
    }
    if (lower.contains('material') || lower.contains('chemical') || lower.contains('molecule')) {
      return 'Materials Science & Chemistry';
    }
    return 'Computer Science & Engineering';
  }
}
