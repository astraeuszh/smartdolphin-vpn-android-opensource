import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../widgets/frosted_glass.dart';

/// 抽屉式选择器：点击后从底部弹出选项列表
class SettingsPickerSheet {
  /// 显示选项列表，点击某项后关闭并返回该值
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<SettingsPickerOption<T>> options,
    required T? currentValue,
    required bool Function(T?, T) isSelected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return HiVpnSheetScaffold(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: HiVpnColors.mutedGray.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
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
                          onTap: () {
                            Navigator.of(ctx).pop(opt.value);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: FrostedGlass(
                            borderRadius: BorderRadius.circular(14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            surface: selected ? GlassSurface.raised : GlassSurface.flat,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    opt.label,
                                    style: theme.textTheme.bodyLarge?.copyWith(
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
                                    size: 22,
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
    );
  }
}

class SettingsPickerOption<T> {
  const SettingsPickerOption({required this.value, required this.label});
  final T value;
  final String label;
}
