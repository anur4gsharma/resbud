import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

bool get isDocxWebEmbedSupported => true;

extension type DocxRenderResult(JSObject _) implements JSObject {
  external JSNumber? get pageCount;
}

@JS('renderDocxToElement')
external JSPromise<DocxRenderResult?>? _renderDocxToElement(
  JSAny containerOrId,
  JSString base64Data,
  JSNumber zoom,
);

@JS('setDocxZoom')
external JSBoolean? _setDocxZoom(
  JSAny containerOrId,
  JSNumber zoom,
);

Widget buildDocxWebEmbed({
  required String viewId,
  required String base64Bytes,
  required double zoom,
  required ValueChanged<int> onPageCountResolved,
  required VoidCallback onError,
}) {
  return _DocxWebEmbedWidget(
    viewId: viewId,
    base64Bytes: base64Bytes,
    zoom: zoom,
    onPageCountResolved: onPageCountResolved,
    onError: onError,
  );
}

class _DocxWebEmbedWidget extends StatefulWidget {
  const _DocxWebEmbedWidget({
    required this.viewId,
    required this.base64Bytes,
    required this.zoom,
    required this.onPageCountResolved,
    required this.onError,
  });

  final String viewId;
  final String base64Bytes;
  final double zoom;
  final ValueChanged<int> onPageCountResolved;
  final VoidCallback onError;

  @override
  State<_DocxWebEmbedWidget> createState() => _DocxWebEmbedWidgetState();
}

class _DocxWebEmbedWidgetState extends State<_DocxWebEmbedWidget> {
  static final Set<String> _registeredViewTypes = {};
  late final String _containerDomId;
  late final String _viewType;
  web.HTMLDivElement? _containerElement;

  @override
  void initState() {
    super.initState();
    _containerDomId = 'docx-container-${widget.viewId}';
    _viewType = 'docx-viewer-${widget.viewId}';

    if (!_registeredViewTypes.contains(_viewType)) {
      _registeredViewTypes.add(_viewType);
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
        final container = web.document.createElement('div') as web.HTMLDivElement;
        container.id = _containerDomId;
        container.style.width = '100%';
        container.style.height = '100%';
        container.style.overflow = 'auto';
        container.style.backgroundColor = '#525659';
        _containerElement = container;
        return container;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerRender();
    });
  }

  @override
  void didUpdateWidget(covariant _DocxWebEmbedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64Bytes != widget.base64Bytes || oldWidget.viewId != widget.viewId) {
      _triggerRender();
    } else if (oldWidget.zoom != widget.zoom) {
      _updateZoom();
    }
  }

  void _triggerRender() {
    if (!mounted || widget.base64Bytes.isEmpty) return;

    // Small delay to ensure DOM element is attached to document tree
    Future<void>.delayed(const Duration(milliseconds: 70), () async {
      if (!mounted) return;
      try {
        final JSAny target = _containerElement != null
            ? _containerElement! as JSObject
            : _containerDomId.toJS;
        final promise = _renderDocxToElement(
          target,
          widget.base64Bytes.toJS,
          widget.zoom.toJS,
        );
        if (promise != null) {
          final result = await promise.toDart;
          if (mounted && result != null) {
            final count = result.pageCount?.toDartInt;
            if (count != null) {
              widget.onPageCountResolved(count);
            }
          }
        } else {
          widget.onError();
        }
      } catch (e) {
        debugPrint('DOCX web render failure: $e');
        if (mounted) widget.onError();
      }
    });
  }

  void _updateZoom() {
    try {
      final JSAny target = _containerElement != null
          ? _containerElement! as JSObject
          : _containerDomId.toJS;
      _setDocxZoom(target, widget.zoom.toJS);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
