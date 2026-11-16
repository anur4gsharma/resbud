import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../generation/generation_models.dart';

/// Authentic paginated document canvas reflecting reference academic typography
/// (Times New Roman serif, 1-inch margins, 1.15 line spacing, 18pt title, 12pt H1).
class DocxDocumentCanvas extends StatefulWidget {
  const DocxDocumentCanvas({
    super.key,
    required this.paper,
    this.zoom = 1.0,
    this.onPageCountResolved,
    this.scrollController,
  });

  final PaperDraftPayload paper;
  final double zoom;
  final ValueChanged<int>? onPageCountResolved;
  final ScrollController? scrollController;

  @override
  State<DocxDocumentCanvas> createState() => _DocxDocumentCanvasState();
}

class _DocxDocumentCanvasState extends State<DocxDocumentCanvas> {
  // A4 dimensions at 96 DPI: 794 x 1123 px
  static const double _basePageWidth = 794.0;
  static const double _basePageMinHeight = 1123.0;
  static const double _baseMargin = 72.0; // 1 inch margin

  late final ScrollController _internalScrollController;

  ScrollController get _activeScrollController =>
      widget.scrollController ?? _internalScrollController;

  @override
  void initState() {
    super.initState();
    _internalScrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportPageCount();
    });
  }

  @override
  void didUpdateWidget(covariant DocxDocumentCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper != widget.paper) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportPageCount();
      });
    }
  }

  @override
  void dispose() {
    _internalScrollController.dispose();
    super.dispose();
  }

  int _calculateEstimatedPages() {
    int totalWords = widget.paper.title.split(RegExp(r'\s+')).length +
        widget.paper.abstractText.split(RegExp(r'\s+')).length;
    for (final section in widget.paper.sections) {
      totalWords += section.heading.split(RegExp(r'\s+')).length;
      totalWords += section.content.split(RegExp(r'\s+')).length;
    }
    for (final ref in widget.paper.references) {
      totalWords += ref.text.split(RegExp(r'\s+')).length;
    }
    // Academic page density: ~400-500 words per page with headings & spacing
    final pages = (totalWords / 450).ceil();
    return pages < 1 ? 1 : pages;
  }

  void _reportPageCount() {
    final pages = _calculateEstimatedPages();
    widget.onPageCountResolved?.call(pages);
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.zoom.clamp(0.4, 2.5);
    final pageWidth = _basePageWidth * zoom;
    final minPageHeight = _basePageMinHeight * zoom;
    final margin = _baseMargin * zoom;

    final estimatedPages = _calculateEstimatedPages();

    return Container(
      color: const Color(0xFF525659), // Classic PDF / Word Reader dark neutral background
      child: SingleChildScrollView(
        key: const ValueKey('docx-document-canvas-scroll-view'),
        controller: _activeScrollController,
        scrollDirection: Axis.vertical,
        padding: EdgeInsets.symmetric(vertical: 24.0 * zoom),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildAllPages(
                estimatedPages,
                pageWidth,
                minPageHeight,
                margin,
                zoom,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAllPages(
    int totalPages,
    double pageWidth,
    double minPageHeight,
    double margin,
    double zoom,
  ) {
    if (totalPages <= 1) {
      return [
        _buildPageContainer(
          pageNumber: 1,
          totalPages: 1,
          pageWidth: pageWidth,
          minHeight: minPageHeight,
          margin: margin,
          zoom: zoom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleSection(zoom),
              if (widget.paper.abstractText.isNotEmpty) ...[
                SizedBox(height: 18 * zoom),
                _buildAbstractSection(zoom),
              ],
              SizedBox(height: 24 * zoom),
              if (widget.paper.pageLayout == 'two_column_academic')
                _buildTwoColumnBody(widget.paper.sections, 1, zoom, includeReferences: true)
              else ...[
                for (var i = 0; i < widget.paper.sections.length; i++)
                  _buildSectionBlock(widget.paper.sections[i], i + 1, zoom),
                if (widget.paper.references.isNotEmpty) ...[
                  SizedBox(height: 24 * zoom),
                  _buildReferencesSection(zoom),
                ],
              ],
            ],
          ),
        ),
      ];
    }

    final sections = widget.paper.sections;
    final totalSections = sections.length;
    final isTwoColumn = widget.paper.pageLayout == 'two_column_academic';

    // Partition sections across totalPages
    final sectionChunks = <List<PaperSectionPayload>>[];
    if (totalSections == 0) {
      for (var i = 0; i < totalPages; i++) {
        sectionChunks.add([]);
      }
    } else if (totalSections <= totalPages) {
      for (var i = 0; i < totalPages; i++) {
        if (i < totalSections) {
          sectionChunks.add([sections[i]]);
        } else {
          sectionChunks.add([]);
        }
      }
    } else {
      final page1Count = (totalSections / totalPages).floor().clamp(1, totalSections);
      sectionChunks.add(sections.take(page1Count).toList());
      var remaining = sections.skip(page1Count).toList();
      final remainingPages = totalPages - 1;

      for (var p = 0; p < remainingPages; p++) {
        final pagesLeft = remainingPages - p;
        final count = (remaining.length / pagesLeft).ceil().clamp(1, remaining.length);
        sectionChunks.add(remaining.take(count).toList());
        remaining = remaining.skip(count).toList();
      }
    }

    var globalSectionIndex = 1;
    final pages = <Widget>[];

    for (var pageIdx = 1; pageIdx <= totalPages; pageIdx++) {
      final isFirstPage = pageIdx == 1;
      final isLastPage = pageIdx == totalPages;
      final currentChunk = sectionChunks[pageIdx - 1];
      final chunkStartIndex = globalSectionIndex;
      globalSectionIndex += currentChunk.length;

      pages.add(
        _buildPageContainer(
          pageNumber: pageIdx,
          totalPages: totalPages,
          pageWidth: pageWidth,
          minHeight: minPageHeight,
          margin: margin,
          zoom: zoom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isFirstPage) ...[
                _buildTitleSection(zoom),
                if (widget.paper.abstractText.isNotEmpty) ...[
                  SizedBox(height: 18 * zoom),
                  _buildAbstractSection(zoom),
                ],
                SizedBox(height: 24 * zoom),
              ] else ...[
                _buildRunningHeader(zoom),
                SizedBox(height: 18 * zoom),
              ],

              if (isTwoColumn)
                _buildTwoColumnBody(
                  currentChunk,
                  chunkStartIndex,
                  zoom,
                  includeReferences: isLastPage,
                )
              else ...[
                for (var i = 0; i < currentChunk.length; i++)
                  _buildSectionBlock(currentChunk[i], chunkStartIndex + i, zoom),
                if (isLastPage && widget.paper.references.isNotEmpty) ...[
                  SizedBox(height: 24 * zoom),
                  _buildReferencesSection(zoom),
                ],
              ],
            ],
          ),
        ),
      );
    }

    return pages;
  }

  Widget _buildRunningHeader(double zoom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.paper.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 8.0 * zoom,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(width: 12 * zoom),
            Text(
              'RESBUD RESEARCH MANUSCRIPT',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 7.5 * zoom,
                color: Colors.grey.shade500,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        SizedBox(height: 4.0 * zoom),
        Divider(color: Colors.grey.shade300, thickness: 0.5 * zoom, height: 1),
      ],
    );
  }

  Widget _buildPageContainer({
    required int pageNumber,
    required int totalPages,
    required double pageWidth,
    required double minHeight,
    required double margin,
    required double zoom,
    required Widget child,
  }) {
    return Container(
      key: ValueKey('docx-page-$pageNumber'),
      width: pageWidth,
      constraints: BoxConstraints(minHeight: minHeight),
      margin: EdgeInsets.only(bottom: 24.0 * zoom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16.0,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Content
          child,
          // Spacing before footer
          SizedBox(height: 24.0 * zoom),
          // Academic Page Footer: clean centered page number
          Padding(
            padding: EdgeInsets.only(top: 24.0 * zoom),
            child: Center(
              child: Text(
                '$pageNumber',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 9.0 * zoom,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnBody(
    List<PaperSectionPayload> sections,
    int startIndex,
    double zoom, {
    bool includeReferences = false,
  }) {
    if (sections.isEmpty) {
      if (includeReferences && widget.paper.references.isNotEmpty) {
        return _buildReferencesSection(zoom, isTwoColumn: true);
      }
      return const SizedBox.shrink();
    }

    final leftWidgets = <Widget>[];
    final rightWidgets = <Widget>[];

    if (sections.length == 1) {
      // Single section on this page (e.g. Introduction on page 1):
      // Flow content blocks across both columns symmetrically to prevent empty right column.
      final sec = sections.first;
      final headingWidget = Padding(
        padding: EdgeInsets.only(bottom: 6.0 * zoom),
        child: Text(
          sec.heading.startsWith(RegExp(r'\d'))
              ? sec.heading
              : '$startIndex. ${sec.heading}',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 11.0 * zoom,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            height: 1.25,
          ),
        ),
      );

      final blocks = _extractContentBlocks(sec.content);
      if (blocks.length <= 1) {
        leftWidgets.add(headingWidget);
        if (blocks.isNotEmpty) {
          leftWidgets.add(_renderSingleBlock(blocks[0], zoom, isTwoColumn: true));
        }
        if (includeReferences && widget.paper.references.isNotEmpty) {
          rightWidgets.add(_buildReferencesSection(zoom, isTwoColumn: true));
        }
      } else {
        final half = (blocks.length / 2).ceil();
        leftWidgets.add(headingWidget);
        for (var i = 0; i < half; i++) {
          leftWidgets.add(_renderSingleBlock(blocks[i], zoom, isTwoColumn: true));
        }
        for (var i = half; i < blocks.length; i++) {
          rightWidgets.add(_renderSingleBlock(blocks[i], zoom, isTwoColumn: true));
        }
        if (includeReferences && widget.paper.references.isNotEmpty) {
          rightWidgets.add(SizedBox(height: 14 * zoom));
          rightWidgets.add(_buildReferencesSection(zoom, isTwoColumn: true));
        }
      }
    } else {
      // Multiple sections: distribute based on block count for balanced visual columns
      final sectionWeights = sections.map((s) => _extractContentBlocks(s.content).length.clamp(1, 999)).toList();
      final totalWeight = sectionWeights.fold(0, (a, b) => a + b);
      var currentWeight = 0;
      var splitIndex = 1;
      for (var i = 0; i < sections.length; i++) {
        currentWeight += sectionWeights[i];
        if (currentWeight >= totalWeight / 2) {
          splitIndex = (i + 1).clamp(1, sections.length - 1);
          break;
        }
      }

      for (var i = 0; i < splitIndex; i++) {
        leftWidgets.add(_buildSectionBlock(sections[i], startIndex + i, zoom, isTwoColumn: true));
      }
      for (var i = splitIndex; i < sections.length; i++) {
        rightWidgets.add(_buildSectionBlock(sections[i], startIndex + i, zoom, isTwoColumn: true));
      }
      if (includeReferences && widget.paper.references.isNotEmpty) {
        rightWidgets.add(SizedBox(height: 14 * zoom));
        rightWidgets.add(_buildReferencesSection(zoom, isTwoColumn: true));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: Colors.grey.shade400, thickness: 0.5 * zoom),
        SizedBox(height: 14 * zoom),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: leftWidgets,
              ),
            ),
            SizedBox(width: 20 * zoom), // 6-8mm inter-column spacing
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rightWidgets,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTitleSection(double zoom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0 * zoom, vertical: 8.0 * zoom),
          child: Text(
            widget.paper.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 18.0 * zoom,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        if (widget.paper.authorInfo != null && widget.paper.authorInfo!.trim().isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0 * zoom, vertical: 2.0 * zoom),
            child: Text(
              widget.paper.authorInfo!.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 11.0 * zoom,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
        if (widget.paper.affiliation != null && widget.paper.affiliation!.trim().isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0 * zoom, vertical: 1.0 * zoom),
            child: Text(
              widget.paper.affiliation!.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 9.5 * zoom,
                fontStyle: FontStyle.italic,
                color: Colors.black54,
              ),
            ),
          ),
        ],
        SizedBox(height: 14 * zoom),
      ],
    );
  }

  Widget _buildAbstractSection(double zoom) {
    if (widget.paper.abstractText.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0 * zoom, vertical: 6.0 * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'ABSTRACT',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 10.0 * zoom,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8 * zoom),
          Text(
            widget.paper.abstractText,
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 10.0 * zoom,
              height: 1.35,
              color: Colors.black,
            ),
          ),
          if (widget.paper.keywords.isNotEmpty) ...[
            SizedBox(height: 8.0 * zoom),
            Align(
              alignment: Alignment.centerLeft,
              child: RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9.5 * zoom,
                    height: 1.3,
                    color: Colors.black,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Index Terms— ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                    ),
                    TextSpan(text: widget.paper.keywords.join(', ')),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 16.0 * zoom),
        ],
      ),
    );
  }

  Widget _buildSectionBlock(
    PaperSectionPayload section,
    int index,
    double zoom, {
    bool isTwoColumn = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: (isTwoColumn ? 14.0 : 18.0) * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Heading (H1 / H2) with clean markdown stripping
          Builder(
            builder: (context) {
              final cleanHeading = section.heading.replaceFirst(RegExp(r'^\s*#+\s*'), '').trim();
              return Text(
                cleanHeading.startsWith(RegExp(r'\d'))
                    ? cleanHeading
                    : '$index. $cleanHeading',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: (isTwoColumn ? 11.0 : 12.5) * zoom,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  height: 1.25,
                ),
              );
            },
          ),
          SizedBox(height: (isTwoColumn ? 4 : 6) * zoom),
          // Section Content rendered as formatted paragraphs
          _renderFormattedContent(section.content, zoom, isTwoColumn: isTwoColumn),
        ],
      ),
    );
  }

  static List<String> _extractContentBlocks(String content) {
    if (content.trim().isEmpty) return [];
    final rawBlocks = content.split('\n\n');
    final blocks = <String>[];
    for (final b in rawBlocks) {
      final lines = b.split('\n');
      final currentProse = StringBuffer();
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('#')) {
          if (currentProse.isNotEmpty) {
            blocks.add(currentProse.toString().trim());
            currentProse.clear();
          }
          blocks.add(trimmedLine);
        } else {
          if (currentProse.isNotEmpty) currentProse.writeln();
          currentProse.write(line);
        }
      }
      if (currentProse.isNotEmpty) {
        blocks.add(currentProse.toString().trim());
      }
    }
    return blocks.where((b) => b.trim().isNotEmpty).toList();
  }

  Widget _buildSubheadingBlock(
    String headingText,
    int level,
    double zoom, {
    bool isTwoColumn = false,
  }) {
    final fontSize = switch (level) {
      1 => (isTwoColumn ? 11.5 : 13.0) * zoom,
      2 => (isTwoColumn ? 10.8 : 12.0) * zoom,
      3 => (isTwoColumn ? 10.0 : 11.0) * zoom,
      _ => (isTwoColumn ? 9.5 : 10.2) * zoom,
    };
    final isItalic = level >= 3;
    final isBold = level <= 3;

    return Padding(
      padding: EdgeInsets.only(
        top: (level <= 2 ? 10.0 : 7.0) * zoom,
        bottom: 4.0 * zoom,
      ),
      child: Text(
        headingText,
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          color: Colors.black87,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _renderSingleBlock(String block, double zoom, {bool isTwoColumn = false}) {
    final trimmed = block.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    // 1. Markdown headings (#, ##, ###, ####)
    if (trimmed.startsWith('#')) {
      final levelMatch = RegExp(r'^(#{1,6})\s*(.*)$').firstMatch(trimmed);
      if (levelMatch != null) {
        final level = levelMatch.group(1)!.length;
        final headingText = levelMatch.group(2)!.trim();
        return _buildSubheadingBlock(headingText, level, zoom, isTwoColumn: isTwoColumn);
      }
    }

    // 2. Markdown table
    if (trimmed.contains('|') &&
        (trimmed.contains('---') ||
            trimmed.split('\n').where((l) => l.trim().startsWith('|')).length >= 2)) {
      return _buildMarkdownTable(trimmed, zoom);
    }

    // 3. Figure / illustration markdown
    if (trimmed.startsWith('![') && trimmed.contains('](') && trimmed.endsWith(')')) {
      return _buildFigureBlock(trimmed, zoom);
    }

    // 4. Chart specification
    if (trimmed.startsWith('```chart') && trimmed.endsWith('```')) {
      return _buildChartBlock(trimmed, zoom);
    }

    // 5. Bullet or numbered list
    if (trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith(RegExp(r'^\d+\.'))) {
      return _buildListBlock(trimmed, zoom);
    }

    // 6. Block math equation
    if ((trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$') && trimmed.length > 4) ||
        (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]') && trimmed.length > 4) ||
        RegExp(r'^\\begin\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}[\s\S]*?\\end\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}$').hasMatch(trimmed)) {
      return _buildMathEquationBlock(trimmed, zoom);
    }

    // 7. Enforce block-level math: split paragraph on embedded equations
    final subWidgets = _splitAndRenderParagraphWithEquations(trimmed, zoom);
    if (subWidgets.length == 1) return subWidgets.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: subWidgets);
  }

  Widget _renderFormattedContent(
    String content,
    double zoom, {
    bool isTwoColumn = false,
  }) {
    if (content.trim().isEmpty) {
      return Text(
        '[Section content pending synthesis]',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: 10.5 * zoom,
          fontStyle: FontStyle.italic,
          color: Colors.grey.shade600,
        ),
      );
    }

    final blocks = _extractContentBlocks(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks
          .map((b) => _renderSingleBlock(b, zoom, isTwoColumn: isTwoColumn))
          .toList(),
    );
  }

  static final RegExp _mathExtractRegex = RegExp(
    r'(`[^`\n]+`)|'
    r'(\\\$)|'
    r'(\\begin\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}[\s\S]*?\\end\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\})|'
    r'(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])|'
    r'(\\\([\s\S]*?\\\))|'
    r'((?<!\\)\$(?!\s)(?!\d+(?:[.,]\d+)?(?:\s|[.,;:!?]|$))(?:[^$\n\\]|\\.)+?(?<!\s)\$(?!\d))',
  );

  static final RegExp _inlineProseTokenRegex = RegExp(
    r'(`[^`\n]+`)|'
    r'(\\\$)|'
    r'(\\\([\s\S]*?\\\))|'
    r'((?<!\\)\$(?!\s)(?!\d+(?:[.,]\d+)?(?:\s|[.,;:!?]|$))(?:[^$\n\\]|\\.)+?(?<!\s)\$(?!\d))|'
    r'(\*\*\*[^*]+\*\*\*|___[^_]+___)|'
    r'(\*\*[^*]+\*\*|__[^_]+__)|'
    r'(\*[^*\n]+\*|(?<=\s)_[^_\n]+_(?=\s|[.,;:!?]|$))',
  );

  static bool _isBigEquation(Match m, String fullText) {
    if (m.group(3) != null) return true;
    if (m.group(4) != null) return true;

    final raw = m.group(0)!;
    if (raw.contains(r'\\')) return true;

    final inner = _cleanMathSource(raw);

    // Large display operators with tall vertical bounds (limits, integrals, products, sums)
    final largeOps = RegExp(r'\\(?:prod|sum|int|iint|iiint|oint|coprod|bigcup|bigcap|lim|max|min|inf|sup)\b');
    if (largeOps.hasMatch(inner)) return true;

    // Complex vertical structures: fractions with relations or compound terms
    if (RegExp(r'\\(?:frac|dfrac|cfrac)\b').hasMatch(inner) &&
        (inner.contains('=') || inner.contains(r'\le') || inner.contains(r'\ge') || inner.contains(r'\sim') || inner.contains(r'\approx') || inner.contains(r'\equiv'))) {
      return true;
    }

    // Standalone equation occupying entire paragraph
    if (fullText.trim() == raw.trim()) {
      if (inner.contains('=') ||
          inner.contains(r'\le') ||
          inner.contains(r'\ge') ||
          inner.contains(r'\sim') ||
          inner.contains(r'\approx') ||
          inner.contains(r'\equiv') ||
          inner.contains(r'\frac')) {
        return true;
      }
    }

    // Equation definitions embedded in introductory prose with equality and substantial length
    if (RegExp(r'(?:=|:=|\\equiv|\\approx)').hasMatch(inner) && inner.length >= 20) {
      return true;
    }

    return false;
  }

  static String _cleanPreEquationProse(String text) {
    var cleaned = text.trim();
    if (cleaned.isEmpty || RegExp(r'^[.,;:!?]+$').hasMatch(cleaned)) {
      return '';
    }
    cleaned = cleaned.replaceAll(RegExp(r'[,;]+$'), '').trim();
    if (RegExp(r'\b(?:calculated|defined|written|expressed|represented|formulated|given)\s+as$', caseSensitive: false).hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(RegExp(r'\s+as$', caseSensitive: false), ' as follows:');
    } else if (RegExp(r'\bas$', caseSensitive: false).hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(RegExp(r'\bas$', caseSensitive: false), 'as follows:');
    } else if (RegExp(r'\b(?:is|given by|satisfies|satisfying|becomes|yields|minimizes the loss)$', caseSensitive: false).hasMatch(cleaned)) {
      if (!cleaned.endsWith(':')) {
        cleaned += ':';
      }
    }
    return cleaned;
  }

  static String _cleanPostEquationProse(String text) {
    var cleaned = text.trim();
    if (cleaned.isEmpty || RegExp(r'^[.,;:!?]+$').hasMatch(cleaned)) {
      return '';
    }
    cleaned = cleaned.replaceAll(RegExp(r'^[,\s;]+'), '').trim();
    if (cleaned.isEmpty || RegExp(r'^[.,;:!?]+$').hasMatch(cleaned)) {
      return '';
    }
    return cleaned;
  }

  static String _cleanMathSource(String raw) {
    var c = raw.trim();
    if ((c.startsWith(r'$$') && c.endsWith(r'$$')) || (c.startsWith(r'\[') && c.endsWith(r'\]'))) {
      return c.substring(2, c.length - 2).trim();
    }
    if (c.startsWith(r'\(') && c.endsWith(r'\)')) {
      return c.substring(2, c.length - 2).trim();
    }
    if (c.startsWith(r'$') && c.endsWith(r'$')) {
      return c.substring(1, c.length - 1).trim();
    }
    return c;
  }

  List<Widget> _splitAndRenderParagraphWithEquations(String text, double zoom) {
    final matches = _mathExtractRegex
        .allMatches(text)
        .where((m) => m.group(1) == null && m.group(2) == null && _isBigEquation(m, text))
        .toList();

    if (matches.isEmpty) {
      return [_buildProseParagraph(text, zoom)];
    }

    final widgets = <Widget>[];
    var cursor = 0;

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final preText = text.substring(cursor, m.start).trim();
      if (preText.isNotEmpty) {
        final cleanedPre = _cleanPreEquationProse(preText);
        if (cleanedPre.isNotEmpty) {
          widgets.add(_buildProseParagraph(cleanedPre, zoom));
        }
      }

      final mathSource = _cleanMathSource(m.group(0)!);
      widgets.add(_buildMathEquationBlock(mathSource, zoom));
      cursor = m.end;
    }

    final postText = text.substring(cursor).trim();
    if (postText.isNotEmpty) {
      final cleanedPost = _cleanPostEquationProse(postText);
      if (cleanedPost.isNotEmpty) {
        widgets.add(_buildProseParagraph(cleanedPost, zoom));
      }
    }

    return widgets;
  }

  Widget _buildMathEquationBlock(String equationText, double zoom) {
    final cleanLatex = _cleanMathSource(equationText);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.0 * zoom),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            cleanLatex,
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: 11.5 * zoom,
              color: Colors.black,
            ),
            onErrorFallback: (_) => Text(
              '[Warning: Unsupported mathematical syntax] $cleanLatex',
              style: TextStyle(
                fontFamily: 'serif',
                fontStyle: FontStyle.italic,
                fontSize: 10.5 * zoom,
                color: const Color(0xFFCC0000),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProseParagraph(String text, double zoom) {
    final bodyStyle = TextStyle(
      fontFamily: 'serif',
      fontSize: 10.5 * zoom,
      height: 1.35,
      color: const Color(0xFF111111),
    );

    if (!text.contains(r'$') && !text.contains(r'\(') && !text.contains('`') && !text.contains('*') && !text.contains('_')) {
      return Padding(
        padding: EdgeInsets.only(bottom: 8.0 * zoom),
        child: Text(
          text,
          textAlign: TextAlign.justify,
          style: bodyStyle,
        ),
      );
    }

    final matches = _inlineProseTokenRegex.allMatches(text);
    if (matches.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: 8.0 * zoom),
        child: Text(
          text,
          textAlign: TextAlign.justify,
          style: bodyStyle,
        ),
      );
    }

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: bodyStyle,
        ));
      }

      final rawToken = match.group(0)!;
      // 1. Code token
      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: rawToken.substring(1, rawToken.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 9.5 * zoom,
            backgroundColor: Colors.black.withValues(alpha: 0.05),
          ),
        ));
      }
      // 2. Escaped dollar
      else if (match.group(2) != null) {
        spans.add(TextSpan(text: r'$', style: bodyStyle));
      }
      // 3 & 4. Inline Math
      else if (match.group(3) != null || match.group(4) != null) {
        final cleanLatex = _cleanMathSource(rawToken);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            cleanLatex,
            mathStyle: MathStyle.text,
            textStyle: bodyStyle,
            onErrorFallback: (_) => Text(
              cleanLatex,
              style: bodyStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ));
      }
      // 5. Bold italic
      else if (match.group(5) != null) {
        spans.add(TextSpan(
          text: rawToken.substring(3, rawToken.length - 3),
          style: bodyStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
        ));
      }
      // 6. Bold
      else if (match.group(6) != null) {
        spans.add(TextSpan(
          text: rawToken.substring(2, rawToken.length - 2),
          style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      }
      // 7. Italic
      else if (match.group(7) != null) {
        spans.add(TextSpan(
          text: rawToken.substring(1, rawToken.length - 1),
          style: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: bodyStyle,
      ));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 8.0 * zoom),
      child: Text.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.justify,
      ),
    );
  }

  Widget _buildMarkdownTable(String tableText, double zoom) {
    final lines = tableText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('|') && l.endsWith('|'))
        .toList();

    if (lines.length < 2) {
      return Text(tableText);
    }

    final headerCols = lines[0]
        .split('|')
        .where((c) => c.isNotEmpty)
        .map((c) => c.trim())
        .toList();

    final dataRows = <List<String>>[];
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].contains('---')) continue; // Skip separator line
      final cols = lines[i]
          .split('|')
          .where((c) => c.isNotEmpty)
          .map((c) => c.trim())
          .toList();
      if (cols.isNotEmpty) dataRows.add(cols);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.0 * zoom),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Colors.grey.shade400, width: 0.75 * zoom),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade100),
              children: headerCols
                  .map((col) => Padding(
                        padding: EdgeInsets.all(6.0 * zoom),
                        child: Text(
                          col,
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 9.5 * zoom,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            for (final row in dataRows)
              TableRow(
                children: row
                    .map((cell) => Padding(
                          padding: EdgeInsets.all(6.0 * zoom),
                          child: Text(
                            cell,
                            style: TextStyle(
                              fontFamily: 'serif',
                              fontSize: 9.0 * zoom,
                            ),
                          ),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListBlock(String listText, double zoom) {
    final items = listText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Padding(
      padding: EdgeInsets.only(left: 12.0 * zoom, bottom: 8.0 * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final numMatch = RegExp(r'^(\d+\.)\s+').firstMatch(item.trim());
          final bullet = numMatch != null ? '${numMatch.group(1)} ' : '• ';
          final cleanItem = item.trim().replaceFirst(RegExp(r'^[-*]\s+|\d+\.\s+'), '');
          return Padding(
            padding: EdgeInsets.only(bottom: 3.0 * zoom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bullet,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 10.5 * zoom,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    cleanItem,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 10.5 * zoom,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChartBlock(String chartText, double zoom) {
    final lines = chartText.replaceAll('```chart', '').replaceAll('```', '').trim().split('\n');
    String title = 'Figure: Quantitative Analysis';
    String ylabel = 'Value';
    List<String> labels = [];
    List<double> values = [];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.toLowerCase().startsWith('title:')) {
        title = line.substring(6).trim().replaceAll("'", '').replaceAll('"', '');
      } else if (line.toLowerCase().startsWith('ylabel:')) {
        ylabel = line.substring(7).trim().replaceAll("'", '').replaceAll('"', '');
      } else if (line.toLowerCase().startsWith('labels:')) {
        final listStr = line.substring(7).replaceAll('[', '').replaceAll(']', '').trim();
        labels = listStr.split(',').map((e) => e.trim().replaceAll("'", '').replaceAll('"', '')).toList();
      } else if (line.toLowerCase().startsWith('values:')) {
        final listStr = line.substring(7).replaceAll('[', '').replaceAll(']', '').trim();
        values = listStr.split(',').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();
      }
    }

    final maxVal = values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 1.0;
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.0 * zoom),
      child: Center(
        child: Container(
          width: 480.0 * zoom,
          padding: EdgeInsets.all(12.0 * zoom),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400, width: 0.75 * zoom),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5 * zoom,
                ),
              ),
              SizedBox(height: 12.0 * zoom),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          values[i].toStringAsFixed(1),
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 8.5 * zoom,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4.0 * zoom),
                        Container(
                          width: 32.0 * zoom,
                          height: (values[i] / effectiveMax * 100.0).clamp(10.0, 100.0) * zoom,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0072B2),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(2.0 * zoom)),
                          ),
                        ),
                        SizedBox(height: 6.0 * zoom),
                        Text(
                          i < labels.length ? labels[i] : 'Item ${i + 1}',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 8.5 * zoom,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              SizedBox(height: 8.0 * zoom),
              Text(
                ylabel,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontStyle: FontStyle.italic,
                  fontSize: 8.5 * zoom,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFigureBlock(String figureText, double zoom) {
    final match = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(figureText);
    if (match == null) return Text(figureText);
    final caption = match.group(1) ?? 'Figure';
    final src = match.group(2) ?? '';

    Widget imageWidget;
    if (src.startsWith('http://') || src.startsWith('https://')) {
      imageWidget = Image.network(
        src,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildPlaceholderFigure(caption, zoom),
      );
    } else if (src.contains('base64,')) {
      try {
        final b64 = src.split('base64,').last.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(b64);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildPlaceholderFigure(caption, zoom),
        );
      } catch (_) {
        imageWidget = _buildPlaceholderFigure(caption, zoom);
      }
    } else if (src.length > 80 && !src.contains(' ') && !src.contains('/')) {
      try {
        final bytes = base64Decode(src.replaceAll(RegExp(r'\s+'), ''));
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildPlaceholderFigure(caption, zoom),
        );
      } catch (_) {
        imageWidget = _buildPlaceholderFigure(caption, zoom);
      }
    } else {
      imageWidget = _buildPlaceholderFigure(caption, zoom);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.0 * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 280.0 * zoom,
              maxWidth: double.infinity,
            ),
            child: Center(child: imageWidget),
          ),
          SizedBox(height: 6.0 * zoom),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'serif',
              fontStyle: FontStyle.italic,
              fontSize: 9.5 * zoom,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderFigure(String caption, double zoom) {
    return Container(
      width: double.infinity,
      height: 120.0 * zoom,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300, width: 1.0 * zoom),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_photo_outlined, size: 32 * zoom, color: Colors.grey.shade600),
          SizedBox(height: 4 * zoom),
          Text(
            caption,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 9.5 * zoom,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferencesSection(double zoom, {bool isTwoColumn = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isTwoColumn) Divider(color: Colors.grey.shade400, thickness: 0.75 * zoom),
        SizedBox(height: (isTwoColumn ? 4 : 8) * zoom),
        Text(
          'REFERENCES',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: (isTwoColumn ? 11.0 : 12.0) * zoom,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: (isTwoColumn ? 6 : 10) * zoom),
        for (var i = 0; i < widget.paper.references.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: (isTwoColumn ? 4.0 : 6.0) * zoom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[${i + 1}] ',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: (isTwoColumn ? 8.5 : 9.5) * zoom,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.paper.references[i].text,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: (isTwoColumn ? 8.5 : 9.5) * zoom,
                      height: 1.25,
                      color: const Color(0xFF222222),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
