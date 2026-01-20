import 'package:flutter/material.dart';
import 'package:review_ai/screens/history_screen.dart'; // For HistorySortOption enum

class FilterOptionsSheet extends StatefulWidget {
  final HistorySortOption currentSortOption;
  final int? currentRatingFilter;

  const FilterOptionsSheet({
    super.key,
    required this.currentSortOption,
    required this.currentRatingFilter,
  });

  @override
  State<FilterOptionsSheet> createState() => _FilterOptionsSheetState();
}

class _FilterOptionsSheetState extends State<FilterOptionsSheet> {
  late HistorySortOption _selectedSortOption;
  late int? _selectedRatingFilter;

  @override
  void initState() {
    super.initState();
    _selectedSortOption = widget.currentSortOption;
    _selectedRatingFilter = widget.currentRatingFilter;
  }

  String getSortOptionLabel(HistorySortOption option) {
    switch (option) {
      case HistorySortOption.latest:
        return '최신순';
      case HistorySortOption.oldest:
        return '오래된순';
      case HistorySortOption.ratingHigh:
        return '별점 높은순';
      case HistorySortOption.ratingLow:
        return '별점 낮은순';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '정렬',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SCDream',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: HistorySortOption.values.map((option) {
                      final isSelected = _selectedSortOption == option;
                      return ChoiceChip(
                        label: Text(
                          getSortOptionLabel(option),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontFamily: 'SCDream',
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.black,
                        backgroundColor: Colors.grey[100],
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedSortOption = option;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '별점 필터',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SCDream',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [
                      ChoiceChip(
                        label: Text(
                          '전체',
                          style: TextStyle(
                            color: _selectedRatingFilter == null
                                ? Colors.white
                                : Colors.black,
                            fontFamily: 'SCDream',
                          ),
                        ),
                        selected: _selectedRatingFilter == null,
                        selectedColor: Colors.black,
                        backgroundColor: Colors.grey[100],
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedRatingFilter = null;
                            });
                          }
                        },
                      ),
                      ...List.generate(5, (index) {
                        final rating = index + 1;
                        final isSelected = _selectedRatingFilter == rating;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              rating,
                              (starIndex) => const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 16,
                              ),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: Colors.black,
                          backgroundColor: Colors.grey[100],
                          onSelected: (selected) {
                            setState(() {
                              _selectedRatingFilter = selected ? rating : null;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'sortOption': _selectedSortOption,
                  'ratingFilter': _selectedRatingFilter,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                '적용',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SCDream',
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
