import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/presentation/providers/location_providers.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/presentation/widgets/common/skeleton_loader.dart';
import 'package:review_ai/presentation/widgets/common/error_widget.dart';
import 'package:review_ai/presentation/widgets/delivery_app_option_list.dart';
import 'package:review_ai/presentation/widgets/restaurant_search/restaurant_state_widgets.dart';
import 'package:review_ai/presentation/widgets/restaurant_search/restaurant_list_widget.dart';
import 'package:review_ai/utils/delivery_app_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:review_ai/config/security_config.dart';
import 'package:review_ai/core/utils/logger_service.dart';

/// 맛집 검색 화면
class RestaurantSearchScreen extends ConsumerStatefulWidget {
  final String foodName;
  final String category;

  const RestaurantSearchScreen({
    super.key,
    required this.foodName,
    required this.category,
  });

  @override
  ConsumerState<RestaurantSearchScreen> createState() =>
      _RestaurantSearchScreenState();
}

class _RestaurantSearchScreenState
    extends ConsumerState<RestaurantSearchScreen> {
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchRestaurants();
    });
    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: SecurityConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          LoggerService.e(
            'Ad load failed (code=${error.code} message=${error.message})',
          );
        },
      ),
    );
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _searchRestaurants() {
    ref
        .read(restaurantSearchProvider.notifier)
        .searchRestaurants(
          foodName: widget.foodName,
          category: widget.category,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(restaurantSearchProvider, (previous, next) {
      if (next.status == RestaurantSearchStatus.noPermission &&
          previous?.status != RestaurantSearchStatus.noPermission) {
        _showPermissionDialog();
      }
    });

    final searchState = ref.watch(restaurantSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: '${widget.foodName} 주변 음식점 리스트',
          child: Text('${widget.foodName} 음식점 리스트'),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _searchRestaurants,
            tooltip: '주변 다시 검색',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(searchState)),
          if (_isBannerAdLoaded && _bannerAd != null)
            SafeArea(
              top: false,
              child: Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(RestaurantSearchState state) {
    if (state.isLoading) {
      return const SkeletonList(
        itemCount: 5,
        itemHeight: 120,
        padding: EdgeInsets.all(16),
      );
    }
    if (state.status == RestaurantSearchStatus.noPermission) {
      return const RestaurantPermissionErrorWidget();
    }
    if (state.status == RestaurantSearchStatus.noLocation) {
      return RestaurantLocationErrorWidget(
        message: state.errorMessage ?? '위치 정보를 가져올 수 없습니다.',
        onRetry: _searchRestaurants,
      );
    }
    if (state.hasError) {
      return Center(
        child: CustomErrorWidget(
          message: _sanitizeErrorMessage(state.errorMessage ?? '오류가 발생했습니다.'),
          onRetry: _searchRestaurants,
        ),
      );
    }
    if (!state.hasRestaurants) {
      return const RestaurantNoResultsWidget();
    }
    return RestaurantListWidget(
      restaurants: state.restaurants,
      foodName: widget.foodName,
      category: widget.category,
      onTapRestaurant: _handleRestaurantTap,
    );
  }

  String _sanitizeErrorMessage(String message) {
    if (message.contains('500') ||
        message.contains('Server error') ||
        message.contains('API') ||
        message.contains('api') ||
        message.contains('Key') ||
        message.contains('key')) {
      return '서버 연결에 문제가 발생했습니다.\n잠시 후 다시 시도해주세요.';
    } else if (message.contains('SocketException') ||
        message.contains('Connection refused') ||
        message.contains('Failed host lookup')) {
      return '인터넷 연결을 확인해주세요.';
    } else if (message.contains('timeout') || message.contains('Timeout')) {
      return '요청 시간이 초과되었습니다.\n인터넷 연결을 확인해주세요.';
    }
    return message;
  }

  void _handleRestaurantTap(KakaoPlace restaurant) {
    final state = ref.read(restaurantSearchProvider);
    DeliveryAppLauncher.launch(
      context,
      restaurant,
      currentLat: state.currentLocation?.latitude,
      currentLng: state.currentLocation?.longitude,
      showDeliveryAppDialog: _showDeliveryAppDialog,
    );
  }

  Future<String?> _showDeliveryAppDialog() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('앱 선택'),
        content: DeliveryAppOptionList(
          onSelect: (value) => Navigator.of(context).pop(value),
        ),
      ),
    );
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('위치 권한 필요'),
        content: const Text(
          '내 주변 맛집을 찾기 위해 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(restaurantSearchProvider.notifier).openAppSettings();
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }
}
