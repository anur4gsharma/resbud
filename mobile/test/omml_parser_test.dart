import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/docx_viewer/omml_parser.dart';

void main() {
  group('OmmlParser Core Unit Tests', () {
    test('parses simple inline variable from m:oMath', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:r><m:t>x</m:t></m:r>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.isDisplay, isFalse);
      expect(res.latex, 'x');
    });

    test('parses display fraction from m:oMathPara', () {
      const xml = '''
<m:oMathPara xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>
  <m:oMath>
    <m:f>
      <m:num><m:r><m:t>a</m:t></m:r></m:num>
      <m:den><m:r><m:t>b</m:t></m:r></m:den>
    </m:f>
  </m:oMath>
</m:oMathPara>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.isDisplay, isTrue);
      expect(res.latex, r'\frac{a}{b}');
    });

    test('parses superscript and subscript correctly', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:sSup>
    <m:e><m:r><m:t>x</m:t></m:r></m:e>
    <m:sup><m:r><m:t>2</m:t></m:r></m:sup>
  </m:sSup>
  <m:r><m:t>+</m:t></m:r>
  <m:sSub>
    <m:e><m:r><m:t>y</m:t></m:r></m:e>
    <m:sub><m:r><m:t>i</m:t></m:r></m:sub>
  </m:sSub>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.latex, '{x}^{2}+{y}_{i}');
    });

    test('parses radical / square root correctly', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:rad>
    <m:e><m:r><m:t>a+b</m:t></m:r></m:e>
  </m:rad>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.latex, r'\sqrt{a+b}');
    });

    test('parses n-ary summation operator with limits', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:nary>
    <m:naryPr><m:chr m:val="∑"/></m:naryPr>
    <m:sub><m:r><m:t>i=1</m:t></m:r></m:sub>
    <m:sup><m:r><m:t>n</m:t></m:r></m:sup>
    <m:e><m:r><m:t>x_i</m:t></m:r></m:e>
  </m:nary>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.latex, contains(r'\sum_{i=1}^{n}'));
    });

    test('parses matrix rows and columns', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:m>
    <m:mr>
      <m:e><m:r><m:t>1</m:t></m:r></m:e>
      <m:e><m:r><m:t>0</m:t></m:r></m:e>
    </m:mr>
    <m:mr>
      <m:e><m:r><m:t>0</m:t></m:r></m:e>
      <m:e><m:r><m:t>1</m:t></m:r></m:e>
    </m:mr>
  </m:m>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.latex, r'\begin{matrix}1 & 0 \\ 0 & 1\end{matrix}');
    });

    test('parses delimiters into left/right parentheses', () {
      const xml = '''
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:d>
    <m:dPr><m:begChr m:val="("/><m:endChr m:val=")"/></m:dPr>
    <m:e><m:r><m:t>x+y</m:t></m:r></m:e>
  </m:d>
</m:oMath>''';
      final res = OmmlParser.parseOmml(xml);
      expect(res.latex, r'\left(x+y\right)');
    });
  });
}
