import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Structured mathematical element parsed from Office Math Markup Language (OMML).
class OmmlMathElement {
  final String latex;
  final bool isDisplay;
  final String? equationNumber;

  const OmmlMathElement({
    required this.latex,
    required this.isDisplay,
    this.equationNumber,
  });
}

/// Structured document block extracted from an OpenXML WordprocessingML document.
abstract class DocxParsedBlock {}

class DocxParagraphBlock extends DocxParsedBlock {
  final List<DocxParagraphSpan> spans;
  final String alignment;

  DocxParagraphBlock({
    required this.spans,
    this.alignment = 'both',
  });
}

class DocxDisplayEquationBlock extends DocxParsedBlock {
  final String latex;
  final String? equationNumber;

  DocxDisplayEquationBlock({
    required this.latex,
    this.equationNumber,
  });
}

abstract class DocxParagraphSpan {}

class DocxTextSpan extends DocxParagraphSpan {
  final String text;
  final bool isBold;
  final bool isItalic;

  DocxTextSpan(
    this.text, {
    this.isBold = false,
    this.isItalic = false,
  });
}

class DocxMathSpan extends DocxParagraphSpan {
  final String latex;

  DocxMathSpan(this.latex);
}

/// Production OMML-to-LaTeX Transpiler and WordprocessingML Document Parser.
///
/// Converts native Microsoft Word math XML (<m:oMath> and <m:oMathPara>) into
/// standard LaTeX mathematical notation for Flutter canvas rendering.
class OmmlParser {
  static const String mathNamespace =
      'http://schemas.openxmlformats.org/officeDocument/2006/math';

  /// Convert an <m:oMath> or <m:oMathPara> XML element or string into standard LaTeX.
  static OmmlMathElement parseOmml(dynamic input) {
    XmlElement element;
    if (input is String) {
      final doc = XmlDocument.parse(input);
      element = doc.rootElement;
    } else if (input is XmlElement) {
      element = input;
    } else {
      throw ArgumentError('Expected String or XmlElement, got ${input.runtimeType}');
    }

    final isDisplay = element.name.local == 'oMathPara' ||
        element.findElements('oMathPara', namespace: mathNamespace).isNotEmpty;

    final oMathNode = element.name.local == 'oMath'
        ? element
        : element.findElements('oMath', namespace: mathNamespace).firstOrNull ?? element;

    final latexBuffer = StringBuffer();
    _transpileOmmlNode(oMathNode, latexBuffer);

    final latex = latexBuffer.toString().trim();
    return OmmlMathElement(
      latex: latex.isEmpty ? '?' : latex,
      isDisplay: isDisplay,
    );
  }

  static void _transpileOmmlNode(XmlNode node, StringBuffer out) {
    for (final child in node.children) {
      if (child is! XmlElement) continue;

      final name = child.name.local;
      switch (name) {
        case 'r': // Run
          _transpileRun(child, out);
          break;

        case 'f': // Fraction: <m:f> <m:num> ... </m:num> <m:den> ... </m:den> </m:f>
          final numElem = child.findElements('num', namespace: mathNamespace).firstOrNull;
          final denElem = child.findElements('den', namespace: mathNamespace).firstOrNull;
          out.write(r'\frac{');
          if (numElem != null) _transpileOmmlNode(numElem, out);
          out.write('}{');
          if (denElem != null) _transpileOmmlNode(denElem, out);
          out.write('}');
          break;

        case 'sSup': // Superscript: <m:sSup> <m:e> base </m:e> <m:sup> exp </m:sup> </m:sSup>
          final baseElem = child.findElements('e', namespace: mathNamespace).firstOrNull;
          final supElem = child.findElements('sup', namespace: mathNamespace).firstOrNull;
          out.write('{');
          if (baseElem != null) _transpileOmmlNode(baseElem, out);
          out.write('}^{');
          if (supElem != null) _transpileOmmlNode(supElem, out);
          out.write('}');
          break;

        case 'sSub': // Subscript: <m:sSub> <m:e> base </m:e> <m:sub> sub </m:sub> </m:sSub>
          final baseElem = child.findElements('e', namespace: mathNamespace).firstOrNull;
          final subElem = child.findElements('sub', namespace: mathNamespace).firstOrNull;
          out.write('{');
          if (baseElem != null) _transpileOmmlNode(baseElem, out);
          out.write('}_{');
          if (subElem != null) _transpileOmmlNode(subElem, out);
          out.write('}');
          break;

        case 'sSubSup': // Subscript + Superscript
          final baseElem = child.findElements('e', namespace: mathNamespace).firstOrNull;
          final subElem = child.findElements('sub', namespace: mathNamespace).firstOrNull;
          final supElem = child.findElements('sup', namespace: mathNamespace).firstOrNull;
          out.write('{');
          if (baseElem != null) _transpileOmmlNode(baseElem, out);
          out.write('}_{');
          if (subElem != null) _transpileOmmlNode(subElem, out);
          out.write('}^{');
          if (supElem != null) _transpileOmmlNode(supElem, out);
          out.write('}');
          break;

        case 'rad': // Radical / Sqrt: <m:rad> <m:deg> optional </m:deg> <m:e> base </m:e> </m:rad>
          final degElem = child.findElements('deg', namespace: mathNamespace).firstOrNull;
          final baseElem = child.findElements('e', namespace: mathNamespace).firstOrNull;
          if (degElem != null && degElem.innerText.trim().isNotEmpty) {
            out.write(r'\sqrt[');
            _transpileOmmlNode(degElem, out);
            out.write(']{');
          } else {
            out.write(r'\sqrt{');
          }
          if (baseElem != null) _transpileOmmlNode(baseElem, out);
          out.write('}');
          break;

        case 'nary': // N-ary operator (Sum, Integral, Product)
          _transpileNary(child, out);
          break;

        case 'd': // Delimiters: <m:d> <m:dPr> ... </m:dPr> <m:e> inner </m:e> </m:d>
          _transpileDelimiter(child, out);
          break;

        case 'm': // Matrix: <m:m> <m:mr> <m:e> ... </m:e> </m:mr> </m:m>
          _transpileMatrix(child, out);
          break;

        case 'box': // Group / Box
        case 'e':
        case 'num':
        case 'den':
        case 'sup':
        case 'sub':
          _transpileOmmlNode(child, out);
          break;

        default:
          _transpileOmmlNode(child, out);
          break;
      }
    }
  }

  static void _transpileRun(XmlElement runElem, StringBuffer out) {
    final tElem = runElem.findElements('t', namespace: mathNamespace).firstOrNull ??
        runElem.findElements('t').firstOrNull;
    if (tElem != null) {
      final text = tElem.innerText;
      out.write(_normalizeMathText(text));
    }
  }

  static void _transpileNary(XmlElement naryElem, StringBuffer out) {
    // Check operator character
    final chrVal = naryElem
        .findElements('naryPr', namespace: mathNamespace)
        .expand((p) => p.findElements('chr', namespace: mathNamespace))
        .map((c) => c.getAttribute('m:val') ?? c.getAttribute('val'))
        .firstOrNull;

    String op = r'\sum';
    if (chrVal != null) {
      if (chrVal.contains('∫') || chrVal.contains(r'\int')) {
        op = r'\int';
      } else if (chrVal.contains('∏') || chrVal.contains(r'\prod')) {
        op = r'\prod';
      }
    }

    final subElem = naryElem.findElements('sub', namespace: mathNamespace).firstOrNull;
    final supElem = naryElem.findElements('sup', namespace: mathNamespace).firstOrNull;
    final baseElem = naryElem.findElements('e', namespace: mathNamespace).firstOrNull;

    out.write(op);
    if (subElem != null && subElem.innerText.trim().isNotEmpty) {
      out.write('_{');
      _transpileOmmlNode(subElem, out);
      out.write('}');
    }
    if (supElem != null && supElem.innerText.trim().isNotEmpty) {
      out.write('^{');
      _transpileOmmlNode(supElem, out);
      out.write('}');
    }
    out.write(' ');
    if (baseElem != null) {
      _transpileOmmlNode(baseElem, out);
    }
  }

  static void _transpileDelimiter(XmlElement dElem, StringBuffer out) {
    final begChr = dElem
            .findElements('dPr', namespace: mathNamespace)
            .expand((p) => p.findElements('begChr', namespace: mathNamespace))
            .map((c) => c.getAttribute('m:val') ?? c.getAttribute('val'))
            .firstOrNull ??
        '(';

    final endChr = dElem
            .findElements('dPr', namespace: mathNamespace)
            .expand((p) => p.findElements('endChr', namespace: mathNamespace))
            .map((c) => c.getAttribute('m:val') ?? c.getAttribute('val'))
            .firstOrNull ??
        ')';

    final innerElem = dElem.findElements('e', namespace: mathNamespace).firstOrNull;

    out.write(r'\left');
    out.write(begChr.isEmpty ? '.' : begChr);
    if (innerElem != null) {
      _transpileOmmlNode(innerElem, out);
    }
    out.write(r'\right');
    out.write(endChr.isEmpty ? '.' : endChr);
  }

  static void _transpileMatrix(XmlElement mElem, StringBuffer out) {
    out.write(r'\begin{matrix}');
    final rows = mElem.findElements('mr', namespace: mathNamespace);
    var firstRow = true;
    for (final row in rows) {
      if (!firstRow) out.write(r' \\ ');
      firstRow = false;

      final cells = row.findElements('e', namespace: mathNamespace);
      var firstCell = true;
      for (final cell in cells) {
        if (!firstCell) out.write(' & ');
        firstCell = false;
        _transpileOmmlNode(cell, out);
      }
    }
    out.write(r'\end{matrix}');
  }

  static String _normalizeMathText(String text) {
    // Map common unicode symbols back to TeX macro representations if needed
    final symbolMap = {
      'α': r'\alpha ',
      'β': r'\beta ',
      'γ': r'\gamma ',
      'δ': r'\delta ',
      'ϵ': r'\epsilon ',
      'θ': r'\theta ',
      'λ': r'\lambda ',
      'μ': r'\mu ',
      'π': r'\pi ',
      'σ': r'\sigma ',
      'τ': r'\tau ',
      'ϕ': r'\phi ',
      'ω': r'\omega ',
      'Δ': r'\Delta ',
      '∑': r'\sum ',
      '∏': r'\prod ',
      '∫': r'\int ',
      '≤': r'\le ',
      '≥': r'\ge ',
      '≠': r'\ne ',
      '≈': r'\approx ',
      '∈': r'\in ',
      '∞': r'\infty ',
      '±': r'\pm ',
      '⋅': r'\cdot ',
      '×': r'\times ',
    };
    return symbolMap[text] ?? text;
  }

  /// Parse a full DOCX file byte array and extract Word paragraphs, text runs, and OMML math blocks.
  static List<DocxParsedBlock> parseDocxArchive(Uint8List docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) return [];

    final xmlString = utf8.decode(docFile.content as List<int>);
    final doc = XmlDocument.parse(xmlString);

    const wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final paragraphs = doc.findAllElements('p', namespace: wNs);

    final blocks = <DocxParsedBlock>[];

    for (final p in paragraphs) {
      // Check if this paragraph is the equation number cell in a 2-cell equation table row
      final parentTc = p.parentElement;
      if (parentTc != null && parentTc.name.local == 'tc') {
        final parentTr = parentTc.parentElement;
        if (parentTr != null && parentTr.name.local == 'tr') {
          final cells = parentTr.findElements('tc', namespace: wNs).toList();
          if (cells.length == 2 && cells[1] == parentTc) {
            final tText = p.findAllElements('t', namespace: wNs).map((e) => e.innerText).join().trim();
            if (RegExp(r'^\(?([0-9]+)\)?$').hasMatch(tText)) {
              continue;
            }
          }
        }
      }

      // Check for equation number in adjacent cell if in a 2-cell equation table
      String? eqNum;
      if (parentTc != null && parentTc.name.local == 'tc') {
        final parentTr = parentTc.parentElement;
        if (parentTr != null && parentTr.name.local == 'tr') {
          final cells = parentTr.findElements('tc', namespace: wNs).toList();
          if (cells.length == 2 && cells[0] == parentTc) {
            final text = cells[1].findAllElements('t', namespace: wNs).map((e) => e.innerText).join().trim();
            final m = RegExp(r'^\(?([0-9]+)\)?$').firstMatch(text);
            if (m != null) {
              eqNum = m.group(1);
            }
          }
        }
      }

      // Check if paragraph contains display math
      final oMathPara = p.findElements('oMathPara', namespace: mathNamespace).firstOrNull;
      if (oMathPara != null) {
        final mathElem = parseOmml(oMathPara);
        blocks.add(DocxDisplayEquationBlock(latex: mathElem.latex, equationNumber: eqNum));
        continue;
      }

      // Check for standalone oMath occupying entire paragraph
      final standaloneOmath = p.findElements('oMath', namespace: mathNamespace);
      final textRuns = p.findElements('r', namespace: wNs);
      if (standaloneOmath.length == 1 && textRuns.isEmpty) {
        final mathElem = parseOmml(standaloneOmath.first);
        blocks.add(DocxDisplayEquationBlock(latex: mathElem.latex, equationNumber: eqNum));
        continue;
      }

      // Mixed paragraph with prose and inline math
      final spans = <DocxParagraphSpan>[];
      for (final child in p.children) {
        if (child is! XmlElement) continue;

        if (child.name.namespaceUri == mathNamespace && child.name.local == 'oMath') {
          final mathElem = parseOmml(child);
          spans.add(DocxMathSpan(mathElem.latex));
        } else if (child.name.namespaceUri == wNs && child.name.local == 'r') {
          final text = child.findElements('t', namespace: wNs).map((t) => t.innerText).join();
          if (text.isNotEmpty) {
            final isBold = child.findElements('rPr', namespace: wNs).expand((rp) => rp.findElements('b', namespace: wNs)).isNotEmpty;
            final isItalic = child.findElements('rPr', namespace: wNs).expand((rp) => rp.findElements('i', namespace: wNs)).isNotEmpty;
            spans.add(DocxTextSpan(text, isBold: isBold, isItalic: isItalic));
          }
        }
      }

      if (spans.isNotEmpty) {
        blocks.add(DocxParagraphBlock(spans: spans));
      }
    }

    return blocks;
  }
}
