import 'package:flutter/material.dart';

/// A widget that displays a list of delivery app options.
///
/// The [onSelect] callback is invoked with the selected app identifier
/// (e.g., 'baemin', 'yogiyo', 'coupang_eats', 'kakao_map').
class DeliveryAppOptionList extends StatelessWidget {
  final void Function(String) onSelect;

  const DeliveryAppOptionList({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOption(context, 'baemin', '배민', '🍱'),
        _buildOption(context, 'yogiyo', '요기요', '🍜'),
        _buildOption(context, 'coupang_eats', '쿠팡이츠', '📦'),
        _buildOption(context, 'kakao_map', '카카오맵', '🗺️'),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context,
    String value,
    String name,
    String emoji,
  ) {
    return RepaintBoundary(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[200],
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(name),
        onTap: () => onSelect(value),
      ),
    );
  }
}
