import 'package:flutter/material.dart';

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
    final zoom = widget.zoom.clamp(0.5, 2.5);
    final pageWidth = _basePageWidth * zoom;
    final minPageHeight = _basePageMinHeight * zoom;
    final margin = _baseMargin * zoom;

    final estimatedPages = _calculateEstimatedPages();

    return Container(
      color: const Color(0xFF525659), // Classic PDF / Word Reader dark neutral background
      child: SingleChildScrollView(
        key: const ValueKey('docx-document-canvas-scroll-view'),
        controller: _activeScrollController,
        padding: EdgeInsets.symmetric(vertical: 24.0 * zoom, horizontal: 16.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Page 1: Title, Abstract, Introduction
              _buildPageContainer(
                pageNumber: 1,
                totalPages: estimatedPages,
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
                    // Display initial sections on page 1
                    for (var i = 0; i < widget.paper.sections.length; i++)
                      _buildSectionBlock(widget.paper.sections[i], i + 1, zoom),
                    if (widget.paper.references.isNotEmpty) ...[
                      SizedBox(height: 24 * zoom),
                      _buildReferencesSection(zoom),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
          // Academic Page Footer
          Padding(
            padding: EdgeInsets.only(top: 24.0 * zoom),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Research Buddy Academic Manuscript',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8.5 * zoom,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  'Page $pageNumber of $totalPages',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9.0 * zoom,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection(double zoom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
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
        SizedBox(height: 10 * zoom),
        Text(
          'Automated Research Synthesis · Generated with Formal Academic Reference Formatting',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 9.5 * zoom,
            fontStyle: FontStyle.italic,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 6 * zoom),
        Divider(color: Colors.grey.shade400, thickness: 0.75 * zoom),
      ],
    );
  }

  Widget _buildAbstractSection(double zoom) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * zoom, vertical: 12 * zoom),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border(
          left: BorderSide(color: Colors.grey.shade400, width: 3.0 * zoom),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABSTRACT',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 10.5 * zoom,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 6 * zoom),
          Text(
            widget.paper.abstractText,
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 10.0 * zoom,
              height: 1.35,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBlock(PaperSectionPayload section, int index, double zoom) {
    return Padding(
      padding: EdgeInsets.only(bottom: 18.0 * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Heading (H1 / H2)
          Text(
            section.heading.startsWith(RegExp(r'\d'))
                ? section.heading
                : '$index. ${section.heading}',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 12.5 * zoom,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.3,
            ),
          ),
          SizedBox(height: 6 * zoom),
          // Section Content rendered as formatted paragraphs
          _renderFormattedContent(section.content, zoom),
        ],
      ),
    );
  }

  Widget _renderFormattedContent(String content, double zoom) {
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

    final paragraphs = content.split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((p) {
        final trimmed = p.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        // Check for Markdown table
        if (trimmed.contains('|') &&
            (trimmed.contains('---') ||
                trimmed.split('\n').where((l) => l.trim().startsWith('|')).length >= 2)) {
          return _buildMarkdownTable(trimmed, zoom);
        }

        // Check for bullet or numbered list
        if (trimmed.startsWith('- ') ||
            trimmed.startsWith('* ') ||
            trimmed.startsWith(RegExp(r'^\d+\.'))) {
          return _buildListBlock(trimmed, zoom);
        }

        // Standard body paragraph: 10.5pt, 1.15 line spacing, 6pt after
        return Padding(
          padding: EdgeInsets.only(bottom: 8.0 * zoom),
          child: Text(
            trimmed,
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 10.5 * zoom,
              height: 1.35,
              color: const Color(0xFF111111),
            ),
          ),
        );
      }).toList(),
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
      child: Table(
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
    );
  }

  Widget _buildListBlock(String listText, double zoom) {
    final items = listText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Padding(
      padding: EdgeInsets.only(left: 12.0 * zoom, bottom: 8.0 * zoom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final cleanItem = item.replaceFirst(RegExp(r'^[-*]\s+|\d+\.\s+'), '');
          return Padding(
            padding: EdgeInsets.only(bottom: 3.0 * zoom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
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

  Widget _buildReferencesSection(double zoom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Colors.grey.shade400, thickness: 0.75 * zoom),
        SizedBox(height: 8 * zoom),
        Text(
          'REFERENCES',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 12.0 * zoom,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 10 * zoom),
        for (var i = 0; i < widget.paper.references.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 6.0 * zoom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[${i + 1}] ',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9.5 * zoom,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.paper.references[i].text,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 9.5 * zoom,
                      height: 1.3,
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
