import 'dart:async';
import 'package:flutter/material.dart';
import 'package:review_ai/utils/network_utils.dart';
import 'package:review_ai/config/security_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:review_ai/config/app_constants.dart';
import 'package:review_ai/models/food_category.dart';
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/providers/food_providers.dart';
import 'package:review_ai/screens/review_screen.dart';
import 'package:review_ai/services/recommendation_service.dart';
import 'package:review_ai/services/user_preference_service.dart';
import 'package:review_ai/utils/responsive.dart';
import 'package:review_ai/viewmodels/today_recommendation_viewmodel.dart';
import 'package:review_ai/widgets/category_card.dart';
import 'package:review_ai/widgets/history/dialogs/food_recommendation_dialog.dart';
import 'package:review_ai/widgets/history/dialogs/user_stats_dialog.dart';
import 'package:review_ai/widgets/common/app_dialogs.dart';

import 'package:review_ai/main.dart'; // usageTrackingServiceProvider import
import 'package:review_ai/services/weather_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:review_ai/widgets/common/skeleton_loader.dart';

class TodayRecommendationScreen extends ConsumerStatefulWidget {
  const TodayRecommendationScreen({super.key});

  @override
  ConsumerState<TodayRecommendationScreen> createState() =>
      _TodayRecommendationScreenState();
}

class _TodayRecommendationScreenState
    extends ConsumerState<TodayRecommendationScreen> {
  final List<String> _loadingMessages = [
    '음식 추천 중...',
    '맛있는 메뉴 찾는 중...',
    'AI가 고민 중...',
    '오늘의 메뉴를 골라볼게요...',
  ];
  int _currentMessageIndex = 0;
  Timer? _messageRotationTimer;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  WeatherCondition? _currentWeather;
  String _weatherMessage = '';

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      // 위치 권한 확인
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      final weather = await WeatherService().getCurrentWeather(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _weatherMessage = _getWeatherMessage(weather);
        });
      }
    } catch (e) {
      debugPrint('Error fetching weather: $e');
    }
  }

  String _getWeatherMessage(WeatherCondition weather) {
    switch (weather) {
      case WeatherCondition.rain:
      case WeatherCondition.drizzle:
      case WeatherCondition.thunderstorm:
        return '비가 오네요 ☔ 뜨끈한 국물이나 파전 어때요?';
      case WeatherCondition.snow:
        return '눈이 내려요 ❄️ 따뜻한 전골 요리 추천해요!';
      case WeatherCondition.clear:
        return '날씨가 참 좋네요 ☀️ 시원한 냉면이나 아이스 커피?';
      case WeatherCondition.clouds:
        return '구름 낀 날 ☁️ 기분 전환할 맛있는 음식!';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _messageRotationTimer?.cancel();
    super.dispose();
  }

  void _startLoadingMessageRotation() {
    _currentMessageIndex = 0;
    _messageRotationTimer?.cancel();
    _messageRotationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _currentMessageIndex =
              (_currentMessageIndex + 1) % _loadingMessages.length;
        });
      }
    });
  }

  void _stopLoadingMessageRotation() {
    _messageRotationTimer?.cancel();
    _messageRotationTimer = null;
  }

  void _loadBannerAd() {
    final adUnitId = SecurityConfig.bannerAdUnitId;
    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
          setState(() {
            _isBannerAdLoaded = false;
          });
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final foodCategories = ref.watch(foodCategoriesProvider);
    final isLoading = ref.watch(todayRecommendationViewModelProvider);

    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: _buildAppBar(context, responsive, textTheme),
          body: _buildBody(context, responsive, foodCategories, textTheme),
          bottomNavigationBar: SafeArea(
            top: false, // 상단은 무시
            child: _buildBottomBannerAd(),
          ),
        ),
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: responsive.iconSize() * 2,
                    height: responsive.iconSize() * 2,
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 4,
                    ),
                  ),
                  SizedBox(height: responsive.verticalSpacing()),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                    child: Text(
                      _loadingMessages[_currentMessageIndex],
                      key: ValueKey<int>(_currentMessageIndex),
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SCDream',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Responsive responsive,
    TextTheme textTheme,
  ) {
    return PreferredSize(
      preferredSize: Size.fromHeight(kToolbarHeight),
      child: SafeArea(
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          titleSpacing: responsive.horizontalPadding(),
          centerTitle: false,
          title: _buildAppBarTitle(responsive, textTheme),
          actions: _buildAppBarActions(context, responsive),
        ),
      ),
    );
  }

  Widget _buildAppBarTitle(Responsive responsive, TextTheme textTheme) {
    return Container(
      alignment: Alignment.centerLeft,
      child: Text(
        '오늘 뭐 먹지?',
        style: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: responsive.appBarFontSize(),
          fontFamily: 'SCDream',
          color: Colors.grey[800],
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    Responsive responsive,
  ) {
    return [
      _buildStatsIconButton(context, responsive),
      _buildReviewIconButton(context, responsive),
    ];
  }

  Widget _buildStatsIconButton(BuildContext context, Responsive responsive) {
    return IconButton(
      icon: Icon(
        Icons.analytics,
        size: responsive.iconSize(),
        color: Colors.black,
      ),
      onPressed: () =>
          showDialog(context: context, builder: (_) => const UserStatsDialog()),
      tooltip: '내 식습관 통계',
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
  }

  Widget _buildReviewIconButton(BuildContext context, Responsive responsive) {
    return IconButton(
      icon: Icon(
        Icons.rate_review,
        size: responsive.iconSize(),
        color: Colors.black,
      ),
      onPressed: () => _navigateToReviewScreen(
        context,
        _createDefaultFood(),
        category: '기타',
      ),
      tooltip: '리뷰 작성',
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
  }

  Widget _buildBody(
    BuildContext context,
    Responsive responsive,
    List<FoodCategory> foodCategories,
    TextTheme textTheme,
  ) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.horizontalPadding(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: responsive.verticalSpacing()),
            _buildBodyHeader(responsive, textTheme),
            SizedBox(height: responsive.verticalSpacing()),
            _buildCategoryGrid(context, responsive, foodCategories),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyHeader(Responsive responsive, TextTheme textTheme) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        vertical: responsive.verticalSpacing() * 0.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_weatherMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                _weatherMessage,
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SCDream',
                ),
              ),
            ),
          Text(
            '카테고리를 선택해주세요',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: responsive.titleFontSize(),
              fontFamily: 'SCDream',
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context,
    Responsive responsive,
    List<FoodCategory> foodCategories,
  ) {
    // 로딩 중이거나 카테고리가 비어있을 때 스켈레톤 표시
    if (foodCategories.isEmpty) {
      return Expanded(
        child: SkeletonGrid(
          itemCount: 6,
          crossAxisCount: responsive.crossAxisCount(),
          childAspectRatio: responsive.childAspectRatio(),
          padding: EdgeInsets.only(
            top: responsive.verticalSpacing(),
            bottom: responsive.verticalSpacing(),
          ),
        ),
      );
    }

    return Expanded(
      child: GridView.builder(
        padding: EdgeInsets.only(
          top: responsive.verticalSpacing(),
          bottom: responsive.verticalSpacing(),
        ),
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: responsive.crossAxisCount(),
          crossAxisSpacing: responsive.horizontalPadding() * 0.5,
          mainAxisSpacing: responsive.verticalSpacing(),
          childAspectRatio: responsive.childAspectRatio(),
        ),
        itemCount: foodCategories.length,
        itemBuilder: (context, index) =>
            _buildCategoryItem(context, foodCategories[index], index),
      ),
    );
  }

  Widget _buildCategoryItem(
    BuildContext context,
    FoodCategory category,
    int index,
  ) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutBack,
      child: CategoryCard(
        category: category,
        onTap: () async {
          // 이미 로딩 중이면 클릭 무시 (중복 클릭 방지)
          final isLoading = ref.read(todayRecommendationViewModelProvider);
          if (isLoading) return;

          final connected = await NetworkUtils.checkInternetConnectivity();
          if (!connected) {
            if (context.mounted) {
              showAppDialog(
                context,
                title: '네트워크 오류',
                message: '인터넷 연결을 확인해주세요.',
                isError: true,
              );
            }
            return;
          }

          final usageTrackingService = ref.read(usageTrackingServiceProvider);
          final hasReachedLimit = await usageTrackingService
              .hasReachedTotalRecommendationLimit();

          if (hasReachedLimit && context.mounted) {
            showAppDialog(
              context,
              title: '일일 추천 한도 초과',
              message: '오늘의 음식 추천 한도에 도달했습니다. 내일 다시 이용해주세요!',
            );
            return;
          }

          await usageTrackingService.incrementTotalRecommendationCount();

          if (context.mounted) {
            _startLoadingMessageRotation();
            ref
                .read(todayRecommendationViewModelProvider.notifier)
                .handleCategoryTap(context, category, _showRecommendationDialog)
                .whenComplete(() {
                  _stopLoadingMessageRotation();
                });
          }
        },
      ),
    );
  }

  Widget _buildBottomBannerAd() {
    if (!_isBannerAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  void _showRecommendationDialog(
    BuildContext context, {
    required String category,
    required List<FoodRecommendation> foods,
    required Color color,
  }) {
    void openDialog() async {
      // 최근 7일간 먹은 음식 가져오기
      final history = await UserPreferenceService.getFoodSelectionHistory();
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final recentFoods = history
          .where((s) => s.selectedAt.isAfter(sevenDaysAgo))
          .map((s) => s.foodName)
          .toSet() // 중복 제거
          .toList();

      final analysis = await UserPreferenceService.analyzeUserPreferences();
      final resultTuple = RecommendationService.pickSmartFood(
        foods,
        recentFoods,
        analysis,
        weather: _currentWeather,
      );
      final recommended = resultTuple.food;
      final reason = resultTuple.reason;

      ref.read(selectedFoodProvider.notifier).state = recommended;

      if (!context.mounted) return;

      final result = await showDialog<dynamic>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (_) => _buildAnimatedDialog(
          context,
          category,
          recommended,
          foods,
          color,
          reason,
        ),
      );

      if (!context.mounted) {
        return;
      }

      await _handleDialogResult(context, result, openDialog);
    }

    openDialog();
  }

  Widget _buildAnimatedDialog(
    BuildContext context,
    String category,
    FoodRecommendation recommended,
    List<FoodRecommendation> foods,
    Color color,
    String reason,
  ) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: ModalRoute.of(context)!.animation!,
              curve: Curves.easeOutBack,
            ),
          ),
      child: FoodRecommendationDialog(
        category: category,
        recommended: recommended,
        foods: foods,
        color: color,
        reason: reason,
      ),
    );
  }

  Future<void> _handleDialogResult(
    BuildContext context,
    dynamic result,
    VoidCallback openDialog,
  ) async {
    if (!context.mounted) return;

    // "근처 음식점 찾기" 버튼 클릭 시 리뷰 프롬프트 표시하지 않음
    if (result == 'search') {
      return;
    }

    if (result == true) {
      final usageTrackingService = ref.read(usageTrackingServiceProvider);
      final hasReachedLimit = await usageTrackingService
          .hasReachedTotalRecommendationLimit();

      if (hasReachedLimit && context.mounted) {
        showAppDialog(
          context,
          title: '일일 추천 한도 초과',
          message: '오늘의 음식 추천 한도에 도달했습니다. 내일 다시 이용해주세요!',
        );
        return;
      }

      await usageTrackingService.incrementTotalRecommendationCount();

      if (context.mounted) {
        openDialog();
      }
    } else {
      await _showReviewPromptIfNeeded(context);
    }
  }

  Future<void> _showReviewPromptIfNeeded(BuildContext context) async {
    final usageTrackingService = ref.read(usageTrackingServiceProvider);
    final currentCount = await usageTrackingService
        .getTotalRecommendationCount();

    if (_shouldShowReviewPrompt(currentCount) && context.mounted) {
      showAppDialog(
        context,
        title: '리뷰 작성 팁!',
        message:
            '추천된 음식이 마음에 드셨나요? 드신 후, 상단의 리뷰 작성 버튼을 눌러 AI를 활용해서 리뷰를 작성해보세요!',
      );
    }
  }

  bool _shouldShowReviewPrompt(int count) {
    return count == 1 || count == 10 || count == 20 || count == 40;
  }

  FoodRecommendation _createDefaultFood() {
    return FoodRecommendation(
      name: AppConstants.defaultFoodName,
      imageUrl: AppConstants.defaultFoodImage,
    );
  }

  void _navigateToReviewScreen(
    BuildContext context,
    FoodRecommendation food, {
    String? category,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(food: food, category: category ?? '기타'),
      ),
    );
  }
}
