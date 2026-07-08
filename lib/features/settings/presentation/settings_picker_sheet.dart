import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../widgets/frosted_glass.dart';

/// 抽屉式选择器：可拖拽高度，松手吸附到常见比例。
class SettingsPickerSheet {
  static const _snapSizes = [0.22, 0.28, 0.35, 0.42, 0.5, 0.58, 0.66, 0.75, 0.85];

  static double _nearestSnap(double fraction) {
    var best = _snapSizes.first;
    var bestDist = (fraction - best).abs();
    for (final s in _snapSizes) {
      final d = (fraction - s).abs();
      if (d < bestDist) {
        best = s;
        bestDist = d;
      }
    }
    return best.clamp(0.2, 0.88);
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<SettingsPickerOption<T>> options,
    required T? currentValue,
    required bool Function(T?, T) isSelected,
    double initialSize = 0.42,
  }) {
    final controller = DraggableScrollableController();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final screenH = MediaQuery.sizeOf(ctx).height;
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            if (n.extent <= 0.19) {
              Navigator.of(ctx).pop();
            }
            return false;
          },
          child: DraggableScrollableSheet(
            controller: controller,
            expand: false,
            minChildSize: 0.18,
            maxChildSize: 0.88,
            initialChildSize: _nearestSnap(initialSize),
            snap: true,
            snapSizes: _snapSizes,
            builder: (context, scrollController) {
              return HiVpnSheetScaffold(
                child: Column(
                  children: [
                    GestureDetector(
                      onVerticalDragUpdate: (d) {
                        if (!controller.isAttached) return;
                        final next = controller.size -
                            d.primaryDelta! / screenH;
                        controller.jumpTo(next.clamp(0.18, 0.88));
                      },
                      onVerticalDragEnd: (_) {
                        if (!controller.isAttached) return;
                        controller.animateTo(
                          _nearestSnap(controller.size),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 12),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: HiVpnColors.mutedGray.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(2),
                          ),
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
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: options.length,
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
                                child: FrostedGlass(
                                  borderRadius: BorderRadius.circular(14),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  surface: selected
                                      ? GlassSurface.raised
                                      : GlassSurface.flat,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          opt.label,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : null,
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
              );
            },
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
