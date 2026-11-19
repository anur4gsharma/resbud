import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Unified persistent bottom action bar for Resbud project inputs.
/// Provides compact, side-by-side Save and Generate actions, safe-area compliance,
/// keyboard visibility awareness, and clear generation progress state.
class ResbudBottomActionBar extends StatelessWidget {
  const ResbudBottomActionBar({
    super.key,
    required this.onSave,
    required this.onGenerate,
    this.isSaving = false,
    this.isGenerating = false,
    this.isDirty = false,
    this.generationStatusMessage,
    this.errorMessage,
    this.onRetry,
    this.generateKey = 'button-generate-paper-bottom',
    this.saveKey = 'button-save-project-bottom',
  });

  final VoidCallback? onSave;
  final VoidCallback? onGenerate;
  final bool isSaving;
  final bool isGenerating;
  final bool isDirty;
  final String? generationStatusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String generateKey;
  final String saveKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    // When keyboard is active, keep bar ultra-compact so it doesn't occlude input fields
    final isKeyboardOpen = keyboardHeight > 100;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? ResbudDesignTokens.surfaceDark : ResbudDesignTokens.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, isKeyboardOpen ? 6 : 8, 14, isKeyboardOpen ? 6 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Generation In-Progress Indicator
              if (isGenerating) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 4),
                      Text(
                        generationStatusMessage ?? 'Synthesizing grounded research paper…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],

              // 2. Failure Recovery Area
              if (!isGenerating && errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 15, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onRetry != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: onRetry,
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // 3. Compact Action Buttons (Save Project & Generate Paper)
              Row(
                children: [
                  // Save Project Button
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      key: ValueKey(saveKey),
                      onPressed: (isSaving || isGenerating) ? null : onSave,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        minimumSize: const Size(0, 38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
                        ),
                      ),
                      icon: isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isDirty ? Icons.save_outlined : Icons.check,
                              size: 16,
                              color: isDirty ? null : Colors.green.shade700,
                            ),
                      label: Text(
                        isSaving ? 'Saving…' : (isDirty ? 'Save' : 'Saved'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Generate Paper Button (Primary CTA)
                  Expanded(
                    flex: 6,
                    child: FilledButton.icon(
                      key: ValueKey(generateKey),
                      onPressed: (isSaving || isGenerating) ? null : onGenerate,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        minimumSize: const Size(0, 38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
                        ),
                      ),
                      icon: isGenerating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                        isGenerating ? 'Generating…' : 'Generate Paper',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
