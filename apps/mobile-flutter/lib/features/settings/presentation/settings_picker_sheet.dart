import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../widgets/frosted_glass.dart';

/// Bottom picker with fixed height for short lists and bounded scrolling for
/// longer lists.
class SettingsPickerSheet {
  static const _rowHeight = 64.0;
  static const _shellHeight = 110.0;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<SettingsPickerOption<T>> options,
    required T? currentValue,
    required bool Function(T?, T) isSelected,
    double initialSize = 0.42,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final screenH = MediaQuery.sizeOf(ctx).height;
        final availableH = screenH * 0.82;
        final contentH = _shellHeight + options.length * _rowHeight;
        final sheetH = contentH.clamp(210.0, availableH);
        final canScroll = contentH > availableH || options.length > 3;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SizedBox(
            height: sheetH,
            child: HiVpnSheetScaffold(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 12),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: HiVpnColors.mutedGray.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      physics: canScroll
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      itemCount: options.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (ctx, i) {
                        final opt = options[i];
                        final selected = isSelected(currentValue, opt.value);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(ctx).pop(opt.value),
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.72)
                                      : theme.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                      spreadRadius: -9,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        opt.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight:
                                              selected ? FontWeight.w600 : null,
                                          color: selected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SettingsPickerOption<T> {
  const SettingsPickerOption({required this.value, required this.label});

  final T value;
  final String label;
}
