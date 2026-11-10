import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../docx_viewer/docx_document_canvas.dart';
import '../export/docx_export_client.dart';
import '../export/docx_file_saver.dart';
import '../generation/generation_models.dart';
import 'pdf_web_embed_stub.dart'
    if (dart.library.js_interop) 'pdf_web_embed.dart';

/// Embedded Native Academic PDF Viewer for Resbud manuscripts.
class PdfViewer extends StatefulWidget {
  const PdfViewer({
    super.key,
    required this.paper,
    this.initialPdfBytes,
    this.exportApi,
    this.fileSaver,
    this.versionSelector,
    this.onSwitchToDocx,
    this.onSwitchToEdit,
    this.onDownload,
    this.onDownloadPdf,
  });

  final PaperDraftPayload paper;
  final Uint8List? initialPdfBytes;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;
  final Widget? versionSelector;
  final VoidCallback? onSwitchToDocx;
  final VoidCallback? onSwitchToEdit;
  final VoidCallback? onDownload;
  final VoidCallback? onDownloadPdf;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  Uint8List? _pdfBytes;
  bool _isExportingPdf = false;
  double _zoom = 1.0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isFullscreen = false;
  bool _useCanvasFallback = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pdfBytes = widget.initialPdfBytes;
    if (kIsWeb && _pdfBytes == null && widget.exportApi != null) {
      _fetchPdfBinary();
    }
  }

  @override
  void didUpdateWidget(covariant PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb && oldWidget.paper != widget.paper) {
      _fetchPdfBinary();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPdfBinary() async {
    if (widget.exportApi == null) return;
    setState(() {
      _isExportingPdf = true;
    });

    try {
      final result = await widget.exportApi!.exportPdf(widget.paper);
      if (!mounted) return;
      setState(() {
        _pdfBytes = result.bytes;
        _isExportingPdf = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('PdfViewer export: using canvas renderer ($e)');
      setState(() {
        _isExportingPdf = false;
        _useCanvasFallback = true;
      });
    }
  }

  void _zoomIn() => setState(() => _zoom = (_zoom + 0.1).clamp(0.5, 2.5));
  void _zoomOut() => setState(() => _zoom = (_zoom - 0.1).clamp(0.5, 2.5));
  void _resetZoom() => setState(() => _zoom = 1.0);
  void _fitToWidth() => setState(() => _zoom = 1.0);

  Future<void> _downloadDocx() async {
    if (widget.onDownload != null) {
      widget.onDownload!();
      return;
    }
    if (widget.exportApi == null || widget.fileSaver == null) return;
    try {
      final result = await widget.exportApi!.exportDocx(widget.paper);
      await widget.fileSaver!.saveDocx(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DOCX download failed: $e')),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (widget.onDownloadPdf != null) {
      widget.onDownloadPdf!();
      return;
    }
    if (widget.exportApi == null || widget.fileSaver == null) return;
    try {
      final result = await widget.exportApi!.exportPdf(widget.paper);
      await widget.fileSaver!.savePdf(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF525659), // Standard PDF grey
      child: Column(
        children: [
          _buildViewerToolbar(),
          Expanded(
            child: Stack(
              children: [
                _buildViewerContent(),
                if (_isExportingPdf && _pdfBytes == null)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Rendering academic PDF layout…'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewerToolbar() {
    return Container(
      key: const ValueKey('pdf-viewer-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF333639),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Version Selector
            if (widget.versionSelector != null) ...[
              widget.versionSelector!,
              const SizedBox(width: 8),
              Container(width: 1, height: 20, color: Colors.white24),
              const SizedBox(width: 8),
            ],

            // Switch to DOCX View button
            if (widget.onSwitchToDocx != null) ...[
              IconButton(
                key: const ValueKey('button-pdf-viewer-switch-docx'),
                tooltip: 'Switch to DOCX View',
                icon: const Icon(Icons.article_outlined, color: Colors.white70, size: 20),
                onPressed: widget.onSwitchToDocx,
              ),
              const SizedBox(width: 4),
            ],

            // Page Navigation
            IconButton(
              key: const ValueKey('button-pdf-page-prev'),
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 20),
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage--);
                      _scrollController.animateTo(
                        (_currentPage - 1) * 800.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  : null,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Page $_currentPage of $_totalPages',
                key: const ValueKey('pdf-page-indicator'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('button-pdf-page-next'),
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
              onPressed: _currentPage < _totalPages
                  ? () {
                      setState(() => _currentPage++);
                      _scrollController.animateTo(
                        (_currentPage - 1) * 800.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  : null,
            ),

            const SizedBox(width: 16),
            Container(width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 16),

            // Zoom Controls
            IconButton(
              key: const ValueKey('button-pdf-zoom-out'),
              tooltip: 'Zoom out',
              icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
              onPressed: _zoom > 0.5 ? _zoomOut : null,
            ),
            GestureDetector(
              onTap: _resetZoom,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '${(_zoom * 100).round()}%',
                  key: const ValueKey('pdf-zoom-indicator'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('button-pdf-zoom-in'),
              tooltip: 'Zoom in',
              icon: const Icon(Icons.add, color: Colors.white70, size: 18),
              onPressed: _zoom < 2.5 ? _zoomIn : null,
            ),
            IconButton(
              key: const ValueKey('button-pdf-fit-width'),
              tooltip: 'Fit to width',
              icon: const Icon(Icons.fit_screen, color: Colors.white70, size: 18),
              onPressed: _fitToWidth,
            ),

            const SizedBox(width: 8),
            Container(width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 8),

            // Download PDF
            IconButton(
              key: const ValueKey('button-pdf-viewer-download'),
              tooltip: 'Download PDF',
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
              onPressed: _downloadPdf,
            ),

            // Download DOCX
            IconButton(
              key: const ValueKey('button-pdf-viewer-download-docx'),
              tooltip: 'Download DOCX',
              icon: const Icon(Icons.download, color: Colors.white70, size: 20),
              onPressed: _downloadDocx,
            ),

            // Switch to Edit
            if (widget.onSwitchToEdit != null) ...[
              IconButton(
                key: const ValueKey('button-pdf-viewer-switch-edit'),
                tooltip: 'Edit & Outline',
                icon: const Icon(Icons.edit_note, color: Colors.white70, size: 20),
                onPressed: widget.onSwitchToEdit,
              ),
            ],

            // Fullscreen
            IconButton(
              key: const ValueKey('button-pdf-viewer-fullscreen'),
              tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () {
                setState(() => _isFullscreen = !_isFullscreen);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerContent() {
    if (_isExportingPdf && _pdfBytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text(
              'Rendering academic PDF manuscript...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (kIsWeb &&
        isPdfWebEmbedSupported &&
        !_useCanvasFallback &&
        _pdfBytes != null &&
        _pdfBytes!.isNotEmpty) {
      final base64Str = base64Encode(_pdfBytes!);
      return buildPdfWebEmbed(
        viewId: 'pdf-${widget.paper.title.hashCode}-${_pdfBytes!.length}',
        base64Bytes: base64Str,
        onError: () {
          if (mounted) setState(() => _useCanvasFallback = true);
        },
      );
    }

    // High fidelity publication canvas fallback (desktop, mobile, headless tests)
    return DocxDocumentCanvas(
      key: ValueKey('pdf-canvas-${widget.paper.hashCode}'),
      paper: widget.paper,
      zoom: _zoom,
      scrollController: _scrollController,
      onPageCountResolved: (count) {
        if (mounted && count != _totalPages) {
          setState(() => _totalPages = count);
        }
      },
    );
  }
}
