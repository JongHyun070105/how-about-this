import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/config/app_constants.dart';
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/providers/review_provider.dart';
import 'package:review_ai/screens/history_screen.dart';
import 'package:review_ai/screens/review_selection_screen.dart';
import 'package:review_ai/utils/responsive.dart';
import 'package:review_ai/viewmodels/review_viewmodel.dart';
import 'package:review_ai/widgets/review/image_upload_section.dart';
import 'package:review_ai/widgets/review/rating_row.dart';
import 'package:review_ai/widgets/common/primary_action_button.dart';
import 'package:review_ai/widgets/common/animated_loading_indicator.dart';
import 'package:review_ai/widgets/review/review_style_section.dart';
import 'package:review_ai/services/image_labeling_service.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final FoodRecommendation food;
  final String category;

  const ReviewScreen({super.key, required this.food, required this.category});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final TextEditingController _foodNameController = TextEditingController();
  bool _hasNavigatedToSelection = false;
  final ImageLabelingService _imageLabelingService = ImageLabelingService();

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  void _initializeScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedFood = widget.food;
      final isDefaultFood = selectedFood.name == AppConstants.defaultFoodName;
      final foodNameToSet = isDefaultFood ? '' : selectedFood.name;

      _foodNameController.text = foodNameToSet;
      ref.read(reviewProvider.notifier).setFoodName(foodNameToSet);

      _hasNavigatedToSelection = false;
    });
  }

  @override
  void dispose() {
    _foodNameController.dispose();
    _imageLabelingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final textTheme = Theme.of(context).textTheme;
    final reviewState = ref.watch(reviewProvider);
    final isLoading = reviewState.isLoading;

    ref.listen(reviewProvider.select((state) => state.foodName), (_, next) {
      if (_foodNameController.text != next) {
        _foodNameController.text = next;
      }
    });

    ref.listen(reviewProvider.select((state) => state.image), (_, next) async {
      if (next != null) {
        final labels = await _imageLabelingService.getLabels(next);
        if (labels.isNotEmpty && context.mounted) {
          final suggestedFood = labels.first;

          // 다이얼로그 대신 자동 입력 및 스낵바 알림
          ref.read(reviewProvider.notifier).setFoodName(suggestedFood);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('음식명이 "$suggestedFood"(으)로 자동 입력되었습니다.'),
              duration: const Duration(seconds: 2),
              action: SnackBarAction(
                label: '취소',
                onPressed: () {
                  ref.read(reviewProvider.notifier).setFoodName('');
                },
              ),
            ),
          );
        }
      }
    });

    ref.listen(reviewProvider.select((state) => state.generatedReviews), (
      previous,
      next,
    ) {
      if (previous?.isEmpty == true &&
          next.isNotEmpty &&
          !_hasNavigatedToSelection &&
          context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && !_hasNavigatedToSelection) {
            _navigateToReviewSelection();
          }
        });
      }
    });

    return PopScope(
      canPop: !isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _hasNavigatedToSelection = false;
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: _buildAppBar(context, responsive, textTheme),
            body: _buildBody(context, responsive, textTheme, isLoading),
          ),
          if (isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  void _navigateToRecommendationScreen() {
    _hasNavigatedToSelection = false;
    Navigator.pop(context);
  }

  void _navigateToHistoryScreen() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const HistoryScreen()),
  );

  void _navigateToReviewSelection() {
    if (!_hasNavigatedToSelection && context.mounted) {
      _hasNavigatedToSelection = true;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReviewSelectionScreen()),
      ).then((_) {
        if (mounted) {
          _hasNavigatedToSelection = false;
          ref.read(reviewProvider.notifier).setGeneratedReviews([]);
        }
      });
    }
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Responsive responsive,
    TextTheme textTheme,
  ) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Text(
        '리뷰 AI',
        style: textTheme.headlineMedium?.copyWith(
          fontSize: responsive.appBarFontSize(),
          fontWeight: FontWeight.bold,
          fontFamily: 'SCDream',
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: responsive.iconSize()),
        onPressed: _navigateToRecommendationScreen,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.history, size: responsive.iconSize()),
          onPressed: _navigateToHistoryScreen,
          tooltip: '히스토리',
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    Responsive responsive,
    TextTheme textTheme,
    bool isLoading,
  ) {
    final reviewState = ref.watch(reviewProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.horizontalPadding(),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: responsive.verticalSpacing() * 0.4),
              Container(
                constraints: BoxConstraints(
                  maxHeight:
                      responsive.screenHeight *
                      (responsive.isTablet ? 0.28 : 0.26),
                ),
                child: const ImageUploadSection(),
              ),
              SizedBox(height: responsive.verticalSpacing() * 0.8),
              _buildSectionLabel(responsive, '음식명'),
              SizedBox(height: responsive.verticalSpacing() * 0.3),
              _buildFoodNameInput(responsive),
              SizedBox(height: responsive.verticalSpacing() * 0.6),
              _buildSectionLabel(responsive, '평점'),
              SizedBox(height: responsive.verticalSpacing() * 0.4),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: Colors.grey[200]!, width: 1.0),
                ),
                child: Column(
                  children: [
                    RatingRow(
                      label: '배달',
                      rating: reviewState.deliveryRating,
                      onRate: (r) => ref
                          .read(reviewProvider.notifier)
                          .setDeliveryRating(r),
                    ),
                    SizedBox(height: responsive.verticalSpacing() * 0.02),
                    RatingRow(
                      label: '맛',
                      rating: reviewState.tasteRating,
                      onRate: (r) =>
                          ref.read(reviewProvider.notifier).setTasteRating(r),
                    ),
                    SizedBox(height: responsive.verticalSpacing() * 0.02),
                    RatingRow(
                      label: '양',
                      rating: reviewState.portionRating,
                      onRate: (r) =>
                          ref.read(reviewProvider.notifier).setPortionRating(r),
                    ),
                    SizedBox(height: responsive.verticalSpacing() * 0.02),
                    RatingRow(
                      label: '가격',
                      rating: reviewState.priceRating,
                      onRate: (r) =>
                          ref.read(reviewProvider.notifier).setPriceRating(r),
                    ),
                  ],
                ),
              ),
              SizedBox(height: responsive.verticalSpacing() * 0.8),
              const ReviewStyleSection(),
              SizedBox(height: responsive.verticalSpacing() * 1.2),
              _buildGenerateButton(isLoading),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(Responsive responsive, String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: responsive.inputFontSize() * 1.1,
          fontWeight: FontWeight.bold,
          fontFamily: 'SCDream',
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildFoodNameInput(Responsive responsive) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey[300]!, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha((255 * 0.05).round()),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        controller: _foodNameController,
        maxLength: AppConstants.maxFoodNameLength,
        autocorrect: false,
        enableSuggestions: false,
        enableInteractiveSelection: false,
        onChanged: (text) =>
            ref.read(reviewProvider.notifier).setFoodName(text),
        style: TextStyle(
          fontFamily: 'SCDream',
          fontSize: responsive.inputFontSize(),
          color: Colors.grey[800],
          decoration: TextDecoration.none,
        ),
        decoration: InputDecoration(
          hintText: '음식명을 입력해주세요',
          counterText: "",
          hintStyle: TextStyle(
            fontFamily: 'SCDream',
            fontSize: responsive.inputFontSize() * 0.9,
            color: Colors.grey[400],
          ),
          border: const UnderlineInputBorder(borderSide: BorderSide.none),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide.none,
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide.none,
          ),
          errorBorder: const UnderlineInputBorder(borderSide: BorderSide.none),
          disabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 16.0,
          ),
          filled: false,
        ),
      ),
    );
  }

  Widget _buildGenerateButton(bool isLoading) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: PrimaryActionButton(
        text: '리뷰 생성하기',
        onPressed: isLoading
            ? null
            : () => ref
                  .read(reviewViewModelProvider.notifier)
                  .generateReviews(context),
        isLoading: false,
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return const AnimatedLoadingIndicator(
      messages: [
        '리뷰 생성 중...',
        'AI가 글을 쓰고 있어요...',
        '맛 표현을 다듬는 중...',
        '거의 다 됐어요!',
      ],
    );
  }
}
