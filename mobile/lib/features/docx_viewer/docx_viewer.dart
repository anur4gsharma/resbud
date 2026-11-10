import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../export/docx_export_client.dart';
import '../export/docx_file_saver.dart';
import '../generation/generation_models.dart';
import 'docx_document_canvas.dart';
import 'docx_web_embed_stub.dart'
    if (dart.library.js_interop) 'docx_web_embed.dart';

/// Embedded Native DOCX Viewer for Research Buddy.
///
/// Provides in-app reading of generated academic research papers with:
/// - Real Word layout via docx-preview in browser or native paginated canvas
/// - Page navigation, page counter (Page X of Y)
/// - Zoom in, zoom out, fit to width, 100% reset
/// - Full-screen viewing
/// - Instant DOCX export and download
class DocxViewer extends StatefulWidget {
  const DocxViewer({
    super.key,
    required this.paper,
    this.initialDocxBytes,
    this.exportApi,
    this.fileSaver,
    this.versionSelector,
    this.onDownload,
    this.onDownloadPdf,
    this.onSwitchToEdit,
    this.isEditMode = false,
  });

  final PaperDraftPayload paper;
  final Uint8List? initialDocxBytes;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;
  final Widget? versionSelector;
  final VoidCallback? onDownload;
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onSwitchToEdit;
  final bool isEditMode;

  @override
  State<DocxViewer> createState() => _DocxViewerState();
}

class _DocxViewerState extends State<DocxViewer> {
  final _scrollController = ScrollController();
  late final PaperExportApi _exportApi;
  late final DocxFileSaver _fileSaver;

  Uint8List? _docxBytes;
  bool _isExportingDocx = false;
  bool _useCanvasFallback = false;

  double _zoom = 1.0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isFullscreen = false;
  int _renderGenerationToken = 0;

  @override
  void initState() {
    super.initState();
    _exportApi = widget.exportApi ?? DocxExportApiClient.fromEnvironment();
    _fileSaver = widget.fileSaver ?? LocalDocxFileSaver();
    _docxBytes = widget.initialDocxBytes;

    if (kIsWeb && _docxBytes == null) {
      _loadDocxBytes();
    }
  }

  @override
  void didUpdateWidget(covariant DocxViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb && oldWidget.paper != widget.paper) {
      _renderGenerationToken++;
      _loadDocxBytes();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDocxBytes() async {
    final token = ++_renderGenerationToken;
    setState(() {
      _isExportingDocx = true;
      _useCanvasFallback = false;
    });

    try {
      final result = await _exportApi.exportDocx(widget.paper);
      if (token != _renderGenerationToken || !mounted) return;
      setState(() {
        _docxBytes = result.bytes;
        _isExportingDocx = false;
      });
    } catch (e) {
      if (token != _renderGenerationToken || !mounted) return;
      debugPrint('DocxViewer export: using canvas renderer ($e)');
      setState(() {
        _isExportingDocx = false;
        _useCanvasFallback = true;
      });
    }
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + 0.1).clamp(0.5, 2.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - 0.1).clamp(0.5, 2.0);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoom = 1.0;
    });
  }

  void _fitToWidth() {
    setState(() {
      // 1.15 is ideal fit for standard viewports
      _zoom = 1.15;
    });
  }

  Future<void> _downloadDocx() async {
    if (widget.onDownload != null) {
      widget.onDownload!();
      return;
    }

    try {
      Uint8List bytesToSave = _docxBytes ?? Uint8List(0);
      if (bytesToSave.isEmpty) {
        final result = await _exportApi.exportDocx(widget.paper);
        bytesToSave = result.bytes;
      }

      final filename = '${widget.paper.title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.docx';
      final path = await _fileSaver.saveDocx(
        bytes: bytesToSave,
        suggestedFilename: filename,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $path'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (widget.onDownloadPdf != null) {
      widget.onDownloadPdf!();
      return;
    }

    try {
      final result = await _exportApi.exportPdf(widget.paper);
      final filename = '${widget.paper.title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.pdf';
      final path = await _fileSaver.savePdf(
        bytes: result.bytes,
        suggestedFilename: filename,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded PDF: $path'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _onPageCountResolved(int count) {
    if (mounted && count != _totalPages) {
      setState(() {
        _totalPages = count > 0 ? count : 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF525659), // Adobe Acrobat / Word Document Reader grey
      child: Column(
        children: [
          // 1. Clean, minimalist Document Viewer Toolbar
          _buildViewerToolbar(),

          // 2. Central Document Canvas
          Expanded(
            child: Stack(
              children: [
                _buildViewerContent(),
                if (_isExportingDocx && _docxBytes == null)
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
                              Text('Rendering academic document layout…'),
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
      key: const ValueKey('docx-viewer-toolbar'),
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
            // Version Selector Pill / Widget
            if (widget.versionSelector != null) ...[
              widget.versionSelector!,
              const SizedBox(width: 8),
              Container(width: 1, height: 20, color: Colors.white24),
              const SizedBox(width: 8),
            ],

            // Page Navigation: Prev, Page X of Y, Next
            IconButton(
              key: const ValueKey('button-docx-page-prev'),
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
                key: const ValueKey('docx-page-indicator'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('button-docx-page-next'),
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

            // Zoom Controls: Zoom Out, Percentage, Zoom In, Fit to Width
            IconButton(
              key: const ValueKey('button-docx-zoom-out'),
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
                  key: const ValueKey('docx-zoom-indicator'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('button-docx-zoom-in'),
              tooltip: 'Zoom in',
              icon: const Icon(Icons.add, color: Colors.white70, size: 18),
              onPressed: _zoom < 2.0 ? _zoomIn : null,
            ),
            IconButton(
              key: const ValueKey('button-docx-fit-width'),
              tooltip: 'Fit to width',
              icon: const Icon(Icons.fit_screen, color: Colors.white70, size: 18),
              onPressed: _fitToWidth,
            ),

            const SizedBox(width: 8),
            Container(width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 8),

            // Download DOCX
            IconButton(
              key: const ValueKey('button-docx-viewer-download'),
              tooltip: 'Download DOCX',
              icon: const Icon(Icons.download, color: Colors.white, size: 20),
              onPressed: _downloadDocx,
            ),

            // Download PDF
            IconButton(
              key: const ValueKey('button-docx-viewer-download-pdf'),
              tooltip: 'Download PDF',
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
              onPressed: _downloadPdf,
            ),

            // Fullscreen Toggle
            IconButton(
              key: const ValueKey('button-docx-viewer-fullscreen'),
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
    // 0. Dedicated loading state while fetching native DOCX binary
    if (_isExportingDocx && _docxBytes == null) {
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
              'Rendering native Word document layout...',
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

    // 1. On Web with DOCX bytes and no canvas override: Use embedded docx-preview
    if (kIsWeb &&
        isDocxWebEmbedSupported &&
        !_useCanvasFallback &&
        _docxBytes != null &&
        _docxBytes!.isNotEmpty) {
      final base64Str = base64Encode(_docxBytes!);
      return buildDocxWebEmbed(
        viewId: 'paper-${widget.paper.title.hashCode}-${_docxBytes!.length}',
        base64Bytes: base64Str,
        zoom: _zoom,
        onPageCountResolved: _onPageCountResolved,
        onError: () {
          if (mounted) setState(() => _useCanvasFallback = true);
        },
      );
    }

    // 2. Native high-fidelity Flutter paginated canvas (desktop, mobile, headless tests, or fallback)
    return DocxDocumentCanvas(
      key: ValueKey('docx-canvas-${widget.paper.hashCode}'),
      paper: widget.paper,
      zoom: _zoom,
      scrollController: _scrollController,
      onPageCountResolved: _onPageCountResolved,
    );
  }
}
