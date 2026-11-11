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

        // Check for figure / illustration markdown
        if (trimmed.startsWith('![') && trimmed.contains('](') && trimmed.endsWith(')')) {
          return _buildFigureBlock(trimmed, zoom);
        }

        // Check for chart specification
        if (trimmed.startsWith('```chart') && trimmed.endsWith('```')) {
          return _buildChartBlock(trimmed, zoom);
        }

        // Check for bullet or numbered list
        if (trimmed.startsWith('- ') ||
            trimmed.startsWith('* ') ||
            trimmed.startsWith(RegExp(r'^\d+\.'))) {
          return _buildListBlock(trimmed, zoom);
        }

        // Check for block math equation
        if ((trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$') && trimmed.length > 4) ||
            (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]') && trimmed.length > 4) ||
            RegExp(r'^\\begin\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}[\s\S]*?\\end\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}$').hasMatch(trimmed)) {
          return _buildMathEquationBlock(trimmed, zoom);
        }

        // Standard body paragraph with potential inline math
        return _buildParagraphWithInlineMath(trimmed, zoom);
      }).toList(),
    );
  }

  Widget _buildMathEquationBlock(String equationText, double zoom) {
    String cleanLatex = equationText.trim();
    if (cleanLatex.startsWith(r'$$') && cleanLatex.endsWith(r'$$')) {
      cleanLatex = cleanLatex.substring(2, cleanLatex.length - 2).trim();
    } else if (cleanLatex.startsWith(r'\[') && cleanLatex.endsWith(r'\]')) {
      cleanLatex = cleanLatex.substring(2, cleanLatex.length - 2).trim();
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.0 * zoom),
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
              equationText,
              style: TextStyle(
                fontFamily: 'serif',
                fontStyle: FontStyle.italic,
                fontSize: 10.5 * zoom,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParagraphWithInlineMath(String text, double zoom) {
    final bodyStyle = TextStyle(
      fontFamily: 'serif',
      fontSize: 10.5 * zoom,
      height: 1.35,
      color: const Color(0xFF111111),
    );

    if (!text.contains(r'$') && !text.contains(r'\(') && !text.contains(r'\[') && !text.contains('`')) {
      return Padding(
        padding: EdgeInsets.only(bottom: 8.0 * zoom),
        child: Text(
          text,
          textAlign: TextAlign.justify,
          style: bodyStyle,
        ),
      );
    }

    final inlineTokenRegex = RegExp(
      r'(`[^`\n]+`)|'
      r'(\\\$)|'
      r'(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])|'
      r'(\\\([\s\S]*?\\\))|'
      r'((?<!\\)\$(?!\s)(?!\d+(?:\s|[.,;:!?]|$))(?:[^$\n\\]|\\.)+?(?<!\s)\$(?!\d))',
    );
    final matches = inlineTokenRegex.allMatches(text);
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
      // 3. Math tokens (display, paren, dollar)
      else {
        String cleanLatex = rawToken;
        if (rawToken.startsWith(r'$$') && rawToken.endsWith(r'$$')) {
          cleanLatex = rawToken.substring(2, rawToken.length - 2).trim();
        } else if (rawToken.startsWith(r'\[') && rawToken.endsWith(r'\]')) {
          cleanLatex = rawToken.substring(2, rawToken.length - 2).trim();
        } else if (rawToken.startsWith(r'$') && rawToken.endsWith(r'$')) {
          cleanLatex = rawToken.substring(1, rawToken.length - 1).trim();
        } else if (rawToken.startsWith(r'\(') && rawToken.endsWith(r'\)')) {
          cleanLatex = rawToken.substring(2, rawToken.length - 2).trim();
        }

        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              cleanLatex,
              mathStyle: MathStyle.text,
              textStyle: TextStyle(
                fontSize: 10.5 * zoom,
                color: Colors.black,
              ),
              onErrorFallback: (_) => Text(
                rawToken,
                style: bodyStyle.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ),
        );
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
