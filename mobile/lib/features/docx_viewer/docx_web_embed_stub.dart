import 'package:flutter/material.dart';

Widget buildDocxWebEmbed({
  required String viewId,
  required String base64Bytes,
  required double zoom,
  required ValueChanged<int> onPageCountResolved,
  required VoidCallback onError,
}) {
  return const SizedBox.shrink();
}

bool get isDocxWebEmbedSupported => false;
