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

class TodayRecommendationScreen extends ConsumerStatefulWidget {
  const TodayRecommendationScreen({super.key});

  @override
  ConsumerState<TodayRecommendationScreen> createState() =>
      _TodayRecommendationScreenState();
}

class _TodayRecommendationScreenState
    extends ConsumerState<TodayRecommendationScreen> {
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    final adUnitId = SecurityConfig.bannerAdUnitId;
    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.fullBanner,
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
    final isCategoryLoading = ref.watch(todayRecommendationViewModelProvider);
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: _buildAppBar(context, responsive, textTheme),
          body: _buildBody(context, responsive, foodCategories, textTheme),
          bottomNavigationBar: SafeArea(child: _buildBottomBannerAd()),
        ),
        if (isCategoryLoading) _buildLoadingOverlay(),
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
      child: Text(
        '카테고리를 선택해주세요',
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: responsive.titleFontSize(),
          fontFamily: 'SCDream',
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context,
    Responsive responsive,
    List<FoodCategory> foodCategories,
  ) {
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
            ref
                .read(todayRecommendationViewModelProvider.notifier)
                .handleCategoryTap(
                  context,
                  category,
                  _showRecommendationDialog,
                );
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
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withAlpha(102),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 3.0),
            SizedBox(height: 20),
            Opacity(
              opacity: 0.0,
              child: Text(
                '음식 추천 불러오는 중...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecommendationDialog(
    BuildContext context, {
    required String category,
    required List<FoodRecommendation> foods,
    required Color color,
  }) {
    final recentFoods = <String>[];

    void openDialog() async {
      final analysis = await UserPreferenceService.analyzeUserPreferences();
      final recommended = RecommendationService.pickSmartFood(
        foods,
        recentFoods,
        analysis,
      );
      ref.read(selectedFoodProvider.notifier).state = recommended;

      if (!context.mounted) return;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) =>
            _buildAnimatedDialog(context, category, recommended, foods, color),
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
      ),
    );
  }

  Future<void> _handleDialogResult(
    BuildContext context,
    bool? result,
    VoidCallback openDialog,
  ) async {
    if (!context.mounted) return;

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
