import 'package:flutter/material.dart';

Widget buildPdfWebEmbed({
  required String viewId,
  required String base64Bytes,
  required VoidCallback onError,
}) {
  return const SizedBox.shrink();
}

bool get isPdfWebEmbedSupported => false;

void setPdfViewerPageWeb(String viewId, int pageNum) {}

void printPdfWeb([String? viewId]) {}
