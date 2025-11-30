import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:review_ai/main.dart';
import 'package:review_ai/providers/food_providers.dart';
import 'package:review_ai/services/recommendation_service.dart';

class UserStatsDialog extends ConsumerStatefulWidget {
  const UserStatsDialog({super.key});

  @override
  ConsumerState<UserStatsDialog> createState() => _UserStatsDialogState();
}

class _UserStatsDialogState extends ConsumerState<UserStatsDialog> {
  late final PageController _pageController;
  int _currentPage = 0;
  Map<String, dynamic>? _stats;
  int _remainingRecommendations = 0;
  int _remainingReviews = 0;
  bool _isLoading = true;
  String? _errorMessage;

  // 상수들을 클래스 레벨에서 정의
  static const int maxRecommendations = 40;
  static const int maxReviews = 5;
  static const int maxPages = 3; // 2에서 3으로 변경

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    try {
      final loadedStats = await RecommendationService.getUserStats();
      final usageTrackingService = ref.read(usageTrackingServiceProvider);
      final remainingRecs = await usageTrackingService
          .getRemainingRecommendationCount();
      final remainingRev = await usageTrackingService.getRemainingReviewCount();

      if (mounted) {
        setState(() {
          _stats = loadedStats;
          _remainingRecommendations = remainingRecs;
          _remainingReviews = remainingRev;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '통계를 불러오는데 실패했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToPage(int page) {
    if (page < 0 || page >= maxPages) return;

    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 768;

    if (_isLoading) {
      return _buildLoadingDialog();
    }

    if (_errorMessage != null) {
      return _buildErrorDialog(_errorMessage!);
    }

    if (_stats == null) {
      return _buildErrorDialog('통계 데이터를 불러올 수 없습니다.');
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.62,
          minWidth: screenSize.width * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildStatsPage(screenSize, isTablet),
                  _buildDayOfWeekPage(screenSize), // 2번째 페이지로 이동
                  _buildCategoryPage(screenSize), // 3번째 페이지로 이동
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingDialog() {
    return const Dialog(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(width: 20),
            Text("불러오는 중...", style: TextStyle(fontFamily: 'Do Hyeon')),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDialog(String message) {
    return CupertinoAlertDialog(
      title: const Text(
        '오류',
        style: TextStyle(fontFamily: 'Do Hyeon', fontWeight: FontWeight.bold),
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: Text(
          message,
          style: const TextStyle(fontFamily: 'Do Hyeon', fontSize: 16),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인', style: TextStyle(fontFamily: 'Do Hyeon')),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        top: 8.0,
        bottom: 8.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48), // Balance for close button
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left, size: 24),
                  onPressed: _currentPage > 0
                      ? () => _navigateToPage(_currentPage - 1)
                      : null,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                Expanded(
                  child: Text(
                    _currentPage == 0
                        ? "통계"
                        : _currentPage == 1
                        ? "요일별 선호 카테고리"
                        : "카테고리별 선호도",
                    style: TextStyle(
                      fontFamily: 'Do Hyeon',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_right, size: 24),
                  onPressed: _currentPage < maxPages - 1
                      ? () => _navigateToPage(_currentPage + 1)
                      : null,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPage(Size screenSize, bool isTablet) {
    final topFoodsList = (_stats!['topFoods'] as List).take(5).toList();
    final usedRecommendations = (maxRecommendations - _remainingRecommendations)
        .clamp(0, maxRecommendations);
    final usedReviews = (maxReviews - _remainingReviews).clamp(0, maxReviews);

    final usageTextStyle = TextStyle(
      fontFamily: 'Do Hyeon',
      fontSize: (screenSize.width * 0.037).clamp(13.0, 18.0),
      color: Colors.grey[700],
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatItem(
              screenSize,
              isTablet,
              "총 선택 횟수",
              "${_stats!['totalSelections']}회",
            ),
            _buildStatItem(
              screenSize,
              isTablet,
              "최근 30일 선택",
              "${_stats!['recentSelections']}회",
            ),
            const SizedBox(height: 10),
            _buildTopFoodsSection(screenSize, isTablet, topFoodsList),
            const SizedBox(height: 16),
            _buildUsageSection(
              screenSize,
              usageTextStyle,
              usedRecommendations,
              usedReviews,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopFoodsSection(
    Size screenSize,
    bool isTablet,
    List topFoodsList,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (screenSize.width * 0.02).clamp(8.0, 16.0),
          ),
          child: const Text(
            "❤️ 선호하는 음식 TOP 5",
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 4), // 8에서 4로 변경
          itemBuilder: (context, index) {
            if (index < topFoodsList.length) {
              final food = topFoodsList[index];
              return _buildStatItem(
                screenSize,
                false,
                food['name'],
                "${food['count']}회",
              );
            } else {
              return _buildStatItem(screenSize, false, "-", "-");
            }
          },
        ),
      ],
    );
  }

  Widget _buildUsageSection(
    Size screenSize,
    TextStyle usageTextStyle,
    int usedRecommendations,
    int usedReviews,
  ) {
    return Column(
      children: [
        _buildUsageIndicator(
          screenSize,
          label: "음식 추천 사용량",
          used: usedRecommendations,
          max: maxRecommendations,
          color: Colors.blue.shade400,
          style: usageTextStyle,
        ),
        const SizedBox(height: 12),
        _buildUsageIndicator(
          screenSize,
          label: "리뷰 사용량",
          used: usedReviews,
          max: maxReviews,
          color: Colors.green.shade400,
          style: usageTextStyle,
        ),
        const SizedBox(height: 12),
        _buildTimeInfo(screenSize),
      ],
    );
  }

  Widget _buildTimeInfo(Size screenSize) {
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (screenSize.width * 0.02).clamp(8.0, 16.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "매일 00:00시에 초기화",
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          Text(
            "현재 시간: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPage(Size screenSize) {
    final foodCategories = ref.watch(foodCategoriesProvider);
    final categoryColorMap = <String, Color>{
      for (final cat in foodCategories) cat.name: cat.color,
    };

    final categoryList = _buildCategoryList(categoryColorMap);

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 16.0,
        left: 16.0,
        right: 16.0,
        top: 8.0,
      ),
      child: categoryList.isEmpty
          ? _buildEmptyCategoryState()
          : _buildCategoryChart(screenSize, categoryList, categoryColorMap),
    );
  }

  List<Map<String, dynamic>> _buildCategoryList(
    Map<String, Color> categoryColorMap,
  ) {
    final totalSelections = _stats!['totalSelections'] ?? 0;
    if (_stats!['categoryStats'] == null ||
        _stats!['categoryStats'] is! Map<String, dynamic>) {
      return [];
    }

    final catStats = Map<String, dynamic>.from(_stats!['categoryStats']);
    final filteredCats = catStats.entries
        .where((e) => e.key != '상관없음' && (e.value ?? 0) > 0)
        .toList();

    final denominator = totalSelections > 0
        ? totalSelections
        : filteredCats.fold<int>(
            0,
            (sum, e) => sum + ((e.value ?? 0) as num).toInt(),
          );

    return filteredCats.map<Map<String, dynamic>>((e) {
      final count = (e.value ?? 0) as int;
      final percent = denominator > 0 ? (count / denominator * 100) : 0.0;
      return {'name': e.key, 'count': count, 'percent': percent};
    }).toList();
  }

  Widget _buildEmptyCategoryState() {
    return const Center(
      child: Text(
        "추천 메뉴에 '좋아요'를 눌러보세요.\n취향을 분석하여 선호도를 알려드릴게요!",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Do Hyeon',
          fontSize: 16,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildCategoryChart(
    Size screenSize,
    List<Map<String, dynamic>> categoryList,
    Map<String, Color> categoryColorMap,
  ) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: _buildAnimatedPieChart(
            screenSize,
            categoryList,
            categoryColorMap,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 2,
          child: _buildCategoryLegend(
            screenSize,
            categoryList,
            categoryColorMap,
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedPieChart(
    Size screenSize,
    List<Map<String, dynamic>> categoryList,
    Map<String, Color> categoryColorMap,
  ) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1000),
      tween: Tween<double>(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, animationValue, child) {
        return PieChart(
          PieChartData(
            sections: categoryList.map((cat) {
              final percent = cat['percent'] ?? 0.0;
              final color =
                  categoryColorMap[cat['name']] ?? Colors.grey.shade400;
              final shouldShowTitle = percent >= 8.0 && animationValue > 0.8;

              return PieChartSectionData(
                color: color,
                value: percent * animationValue,
                title: shouldShowTitle ? '${percent.toStringAsFixed(0)}%' : '',
                radius: screenSize.width * 0.22,
                titleStyle: TextStyle(
                  fontSize: shouldShowTitle ? (percent >= 15 ? 16 : 14) : 0,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontFamily: 'Do Hyeon',
                ),
                titlePositionPercentageOffset: percent >= 15
                    ? 0.6
                    : (percent >= 8 ? 0.7 : 0.8),
              );
            }).toList(),
            pieTouchData: PieTouchData(enabled: true),
            borderData: FlBorderData(show: false),
            sectionsSpace: 3,
            centerSpaceRadius: screenSize.width * 0.12,
            startDegreeOffset: 270,
          ),
        );
      },
    );
  }

  Widget _buildCategoryLegend(
    Size screenSize,
    List<Map<String, dynamic>> categoryList,
    Map<String, Color> categoryColorMap,
  ) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween<double>(begin: 0, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, animationValue, child) {
        return Opacity(
          opacity: animationValue.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + (animationValue.clamp(0.0, 1.0) * 0.3),
            child: _buildLegendContent(
              screenSize,
              categoryList,
              categoryColorMap,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendContent(
    Size screenSize,
    List<Map<String, dynamic>> categoryList,
    Map<String, Color> categoryColorMap,
  ) {
    return Center(
      child: Column(
        children: [
          Wrap(
            spacing: 12.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.center,
            children: categoryList
                .take(4)
                .map(
                  (cat) => _buildLegendItem(screenSize, cat, categoryColorMap),
                )
                .toList(),
          ),
          if (categoryList.length > 4)
            Wrap(
              spacing: 12.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: categoryList
                  .skip(4)
                  .take(3)
                  .map(
                    (cat) =>
                        _buildLegendItem(screenSize, cat, categoryColorMap),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(
    Size screenSize,
    Map<String, dynamic> cat,
    Map<String, Color> categoryColorMap,
  ) {
    final color = categoryColorMap[cat['name']] ?? Colors.grey.shade400;
    final percent = cat['percent'] ?? 0.0;

    return Container(
      constraints: BoxConstraints(maxWidth: screenSize.width * 0.25),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cat['name'],
                  style: const TextStyle(
                    fontFamily: 'Do Hyeon',
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${percent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontFamily: 'Do Hyeon',
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    Size screenSize,
    bool isTablet,
    String label,
    String value,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: (screenSize.height * 0.008).clamp(4.0, 8.0),
        horizontal: (screenSize.width * 0.02).clamp(8.0, 16.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Do Hyeon',
                fontSize: (screenSize.width * (isTablet ? 0.025 : 0.035)).clamp(
                  12.0,
                  18.0,
                ),
                color: Colors.grey[700],
              ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          SizedBox(width: (screenSize.width * 0.04).clamp(12.0, 20.0)),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Do Hyeon',
                fontSize: (screenSize.width * (isTablet ? 0.028 : 0.038)).clamp(
                  14.0,
                  20.0,
                ),
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageIndicator(
    Size screenSize, {
    required String label,
    required int used,
    required int max,
    required Color color,
    required TextStyle style,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (screenSize.width * 0.02).clamp(8.0, 16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: $used / $max", style: style),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: max > 0 ? used / max : 0,
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ],
      ),
    );
  }

  Widget _buildDayOfWeekPage(Size screenSize) {
    final dayOfWeekPrefs = (_stats!['dayOfWeekPreferences'] as Map?) ?? {};

    if (dayOfWeekPrefs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "아직 요일별 데이터가 없습니다.\n음식을 추천받고 '좋아요'를 눌러보세요!",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    final weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final foodCategories = ref.watch(foodCategoriesProvider);
    final categoryColorMap = <String, Color>{
      for (final cat in foodCategories) cat.name: cat.color,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.separated(
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final weekday = index + 1;
          final categoryData = (dayOfWeekPrefs[weekday] as Map?) ?? {};

          if (categoryData.isEmpty) {
            return _buildDayCard(
              screenSize,
              weekdayNames[index],
              '-',
              Colors.grey.shade300,
              0,
            );
          }

          final sortedCategories = categoryData.entries.toList()
            ..sort((a, b) => (b.value as int).compareTo(a.value as int));

          final topCategory = sortedCategories.first.key as String;
          final count = sortedCategories.first.value as int;
          final color = categoryColorMap[topCategory] ?? Colors.grey.shade400;

          return _buildDayCard(
            screenSize,
            weekdayNames[index],
            topCategory,
            color,
            count,
          );
        },
      ),
    );
  }

  Widget _buildDayCard(
    Size screenSize,
    String day,
    String category,
    Color color,
    int count,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.04,
        vertical: screenSize.height * 0.015,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: screenSize.width * 0.12,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontFamily: 'Do Hyeon',
                  fontSize: screenSize.width * 0.035,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ),
          SizedBox(width: screenSize.width * 0.04),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category == '-' ? '데이터 없음' : category,
                    style: TextStyle(
                      fontFamily: 'Do Hyeon',
                      fontSize: screenSize.width * 0.04,
                      color: category == '-'
                          ? Colors.grey
                          : Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(51),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count회',
                      style: TextStyle(
                        fontFamily: 'Do Hyeon',
                        fontSize: screenSize.width * 0.032,
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
