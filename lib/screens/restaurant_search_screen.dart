import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/location_providers.dart';
import '../models/location_models.dart';

import 'package:review_ai/widgets/common/skeleton_loader.dart';
import '../widgets/common/error_widget.dart';
import '../widgets/delivery_app_option_list.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/security_config.dart';

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
    // 화면 진입 시 자동으로 맛집 검색
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
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint(
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
        title: Text('${widget.foodName} 음식점 리스트'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _searchRestaurants,
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
      return _buildPermissionError(state.errorMessage ?? '위치 권한이 필요합니다.');
    }

    if (state.status == RestaurantSearchStatus.noLocation) {
      return _buildLocationError(state.errorMessage ?? '위치 정보를 가져올 수 없습니다.');
    }

    if (state.hasError) {
      String errorMessage = state.errorMessage ?? '오류가 발생했습니다.';

      // 에러 메시지 순화 - 기술적인 내용 제거
      if (errorMessage.contains('500') ||
          errorMessage.contains('Server error') ||
          errorMessage.contains('API') ||
          errorMessage.contains('api') ||
          errorMessage.contains('Key') ||
          errorMessage.contains('key')) {
        errorMessage = '서버 연결에 문제가 발생했습니다.\n잠시 후 다시 시도해주세요.';
      } else if (errorMessage.contains('SocketException') ||
          errorMessage.contains('Connection refused') ||
          errorMessage.contains('Failed host lookup')) {
        errorMessage = '인터넷 연결을 확인해주세요.';
      } else if (errorMessage.contains('timeout') ||
          errorMessage.contains('Timeout')) {
        errorMessage = '요청 시간이 초과되었습니다.\n인터넷 연결을 확인해주세요.';
      }

      return Center(
        child: CustomErrorWidget(
          message: errorMessage,
          onRetry: _searchRestaurants,
        ),
      );
    }

    if (!state.hasRestaurants) {
      return _buildNoResults();
    }

    return _buildRestaurantList(state.restaurants);
  }

  Widget _buildPermissionError(String message) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_disabled,
              size: screenWidth * 0.16,
              color: Colors.orange[300],
            ),
            SizedBox(height: screenHeight * 0.02),
            Text(
              '위치 권한이 필요합니다',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: screenHeight * 0.015),
            Text(
              '내 주변 맛집을 찾기 위해 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해주세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: screenHeight * 0.04),
            ElevatedButton.icon(
              onPressed: () {
                ref
                    .read(restaurantSearchProvider.notifier)
                    .requestLocationPermission();
              },
              icon: const Icon(Icons.check),
              label: const Text('권한 허용하기'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.06,
                  vertical: screenHeight * 0.015,
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
            TextButton(
              onPressed: () {
                ref.read(restaurantSearchProvider.notifier).openAppSettings();
              },
              child: const Text('설정으로 이동'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationError(String message) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_searching,
              size: screenWidth * 0.16,
              color: Colors.grey,
            ),
            SizedBox(height: screenHeight * 0.02),
            Text(
              '위치를 찾을 수 없습니다',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: screenHeight * 0.03),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(restaurantSearchProvider.notifier)
                    .clearLocationCache();
                _searchRestaurants();
              },
              child: const Text('다시 시도'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref
                    .read(restaurantSearchProvider.notifier)
                    .openLocationSettings();
              },
              child: const Text('위치 설정 열기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: screenWidth * 0.16,
              color: Colors.grey,
            ),
            SizedBox(height: screenHeight * 0.02),
            Text(
              '근처에 맛집이 없습니다',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              '다른 음식으로 검색해보세요',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantList(List<KakaoPlace> restaurants) {
    return Column(
      children: [
        // 검색 정보 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${restaurants.length}개의 음식점을 찾았습니다',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.foodName} • ${widget.category}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        // 맛집 리스트
        Expanded(
          child: ListView.builder(
            itemCount: restaurants.length,
            itemBuilder: (context, index) {
              final restaurant = restaurants[index];
              return _buildRestaurantCard(restaurant);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRestaurantCard(KakaoPlace restaurant) {
    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          title: Text(
            restaurant.placeName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                restaurant.roadAddressName ?? restaurant.addressName,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              if (restaurant.phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  restaurant.phone,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  if (restaurant.distanceFormatted.isNotEmpty) ...[
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      restaurant.distanceFormatted,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        restaurant.categoryName,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: const IconButton(
            icon: Icon(Icons.delivery_dining),
            onPressed: null,
          ),
          onTap: () => _launchDeliveryApp(restaurant),
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
              Navigator.of(context).pop(); // 화면 종료
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

  /// 배달앱으로 이동합니다.
  Future<void> _launchDeliveryApp(KakaoPlace restaurant) async {
    try {
      // 배달앱 선택 다이얼로그 표시
      final selectedApp = await _showDeliveryAppDialog();
      if (selectedApp == null) return;

      switch (selectedApp) {
        case 'baemin':
        case 'yogiyo':
        case 'coupang_eats':
          await _launchOtherDeliveryApp(restaurant, selectedApp);
          break;
        case 'kakao_map':
          await _launchKakaoMap(restaurant);
          break;
        default:
          return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('앱을 실행하는 중 오류가 발생했습니다.')));
      }
    }
  }

  /// 다른 배달앱 실행 (배민, 요기요, 쿠팡이츠)
  Future<void> _launchOtherDeliveryApp(
    KakaoPlace restaurant,
    String appName,
  ) async {
    // 1. 클립보드에 음식점 이름 복사
    await Clipboard.setData(ClipboardData(text: restaurant.placeName));

    // 2. 스낵바로 안내
    if (mounted) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('📋 복사 완료!'),
          content: Text(
            '"${restaurant.placeName}"이(가)\n클립보드에 복사되었습니다.\n\n'
            '앱에서 검색창에 붙여넣기하여\n주문하세요!',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('앱 열기'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;
    }

    // 3. URL Scheme으로 앱 열기 (딥링크)
    List<String> urlSchemes;
    String packageName;
    String appDisplayName;

    switch (appName) {
      case 'baemin':
        urlSchemes = ['baemin://'];
        packageName = 'com.sampleapp';
        appDisplayName = '배민';
        break;
      case 'yogiyo':
        urlSchemes = ['yogiyoapp://open'];
        packageName = 'com.fineapp.yogiyo';
        appDisplayName = '요기요';
        break;
      case 'coupang_eats':
        urlSchemes = ['coupangeats://'];
        packageName = 'com.coupang.mobile.eats';
        appDisplayName = '쿠팡이츠';
        break;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알 수 없는 앱입니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
    }

    // Android에서만 작동
    if (Theme.of(context).platform != TargetPlatform.android) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이 기능은 Android에서만 지원됩니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 여러 URL Scheme을 순차적으로 시도
    bool launchSuccess = false;
    for (final urlScheme in urlSchemes) {
      try {
        final uri = Uri.parse(urlScheme);
        final canLaunch = await canLaunchUrl(uri);

        if (canLaunch) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launchSuccess = true;
          break; // 성공하면 반복 중단
        }
      } catch (e) {
        // 해당 scheme 실패, 다음 scheme 시도
        continue;
      }
    }

    // 모든 scheme이 실패한 경우
    if (!launchSuccess && mounted) {
      final shouldOpenStore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$appDisplayName 앱'),
          content: Text(
            '$appDisplayName 앱을 실행할 수 없습니다.\n\nPlay Store에서 앱을 설치 또는 업데이트하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Play Store 열기'),
            ),
          ],
        ),
      );

      if (shouldOpenStore == true) {
        final storeUri = Uri.parse('market://details?id=$packageName');
        try {
          await launchUrl(storeUri, mode: LaunchMode.externalApplication);
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Play Store를 열 수 없습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 카카오맵 실행
  Future<void> _launchKakaoMap(KakaoPlace restaurant) async {
    try {
      // 현재 위치 가져오기
      final searchState = ref.read(restaurantSearchProvider);
      final currentLocation = searchState.currentLocation;
      final latitude = currentLocation?.latitude;
      final longitude = currentLocation?.longitude;

      String appScheme;
      String webUrl;

      if (latitude != null && longitude != null) {
        // 출발지 좌표가 있는 경우: 길찾기 모드
        final startLat = latitude;
        final startLng = longitude;
        final startName = Uri.encodeComponent('내 위치');
        final endName = Uri.encodeComponent(restaurant.placeName);

        appScheme =
            'kakaomap://route?'
            'sp=$startLat,$startLng&'
            'ep=${restaurant.y},${restaurant.x}&'
            'sn=$startName&'
            'en=$endName';

        webUrl =
            'https://map.kakao.com/link/to/'
            '${restaurant.placeName},${restaurant.y},${restaurant.x}/'
            'from/내 위치,$startLat,$startLng';
      } else {
        // 출발지 좌표가 없는 경우: 장소 보기 모드
        appScheme = 'kakaomap://look?p=${restaurant.y},${restaurant.x}&app=1';
        webUrl =
            'https://map.kakao.com/link/map/${restaurant.placeName},${restaurant.y},${restaurant.x}';
      }

      final uri = Uri.parse(appScheme);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // 앱이 없으면 웹으로
        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카카오맵을 실행할 수 없습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 배달앱 선택 다이얼로그
  Future<String?> _showDeliveryAppDialog() async {
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
}
