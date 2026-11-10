import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

bool get isPdfWebEmbedSupported => true;

extension type PdfRenderResult(JSObject _) implements JSObject {
  external JSBoolean? get success;
  external JSString? get url;
}

@JS('renderPdfToElement')
external JSPromise<PdfRenderResult?>? _renderPdfToElement(
  JSAny containerOrId,
  JSString base64Data,
);

Widget buildPdfWebEmbed({
  required String viewId,
  required String base64Bytes,
  required VoidCallback onError,
}) {
  return _PdfWebEmbedWidget(
    viewId: viewId,
    base64Bytes: base64Bytes,
    onError: onError,
  );
}

class _PdfWebEmbedWidget extends StatefulWidget {
  const _PdfWebEmbedWidget({
    required this.viewId,
    required this.base64Bytes,
    required this.onError,
  });

  final String viewId;
  final String base64Bytes;
  final VoidCallback onError;

  @override
  State<_PdfWebEmbedWidget> createState() => _PdfWebEmbedWidgetState();
}

class _PdfWebEmbedWidgetState extends State<_PdfWebEmbedWidget> {
  static final Set<String> _registeredViewTypes = {};
  late final String _containerDomId;
  late final String _viewType;
  web.HTMLDivElement? _containerElement;

  @override
  void initState() {
    super.initState();
    _containerDomId = 'pdf-container-${widget.viewId}';
    _viewType = 'pdf-viewer-${widget.viewId}';

    if (!_registeredViewTypes.contains(_viewType)) {
      _registeredViewTypes.add(_viewType);
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
        final container = web.document.createElement('div') as web.HTMLDivElement;
        container.id = _containerDomId;
        container.style.width = '100%';
        container.style.height = '100%';
        container.style.overflow = 'hidden';
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
  void didUpdateWidget(covariant _PdfWebEmbedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64Bytes != widget.base64Bytes || oldWidget.viewId != widget.viewId) {
      _triggerRender();
    }
  }

  void _triggerRender() {
    if (!mounted || widget.base64Bytes.isEmpty) return;

    Future<void>.delayed(const Duration(milliseconds: 70), () async {
      if (!mounted) return;
      try {
        final JSAny target = _containerElement != null
            ? _containerElement! as JSObject
            : _containerDomId.toJS;
        final promise = _renderPdfToElement(
          target,
          widget.base64Bytes.toJS,
        );
        if (promise != null) {
          await promise.toDart;
        } else {
          widget.onError();
        }
      } catch (e) {
        debugPrint('PDF web render failure: $e');
        if (mounted) widget.onError();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
