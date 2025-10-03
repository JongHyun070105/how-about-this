import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/location_providers.dart';
import '../models/location_models.dart';
import '../widgets/common/loading_widget.dart';
import '../widgets/common/error_widget.dart';

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
  @override
  void initState() {
    super.initState();
    // 화면 진입 시 자동으로 맛집 검색
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchRestaurants();
    });
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
    final searchState = ref.watch(restaurantSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.foodName} 맛집'),
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
      body: _buildBody(searchState),
    );
  }

  Widget _buildBody(RestaurantSearchState state) {
    if (state.isLoading) {
      return const Center(child: LoadingWidget(message: '근처 맛집을 찾고 있습니다...'));
    }

    if (state.status == RestaurantSearchStatus.noPermission) {
      return _buildPermissionError(state.errorMessage ?? '위치 권한이 필요합니다.');
    }

    if (state.status == RestaurantSearchStatus.noLocation) {
      return _buildLocationError(state.errorMessage ?? '위치 정보를 가져올 수 없습니다.');
    }

    if (state.hasError) {
      return Center(
        child: CustomErrorWidget(
          message: state.errorMessage ?? '오류가 발생했습니다.',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '위치 권한이 필요합니다',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(restaurantSearchProvider.notifier)
                    .requestLocationPermission();
              },
              child: const Text('권한 허용'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(restaurantSearchProvider.notifier).openAppSettings();
              },
              child: const Text('설정에서 허용'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_searching, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '위치를 찾을 수 없습니다',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '근처에 맛집이 없습니다',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '다른 음식으로 검색해보세요',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('돌아가기'),
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
                '${restaurants.length}개의 맛집을 찾았습니다',
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
    return Card(
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
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    restaurant.distanceFormatted,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Container(
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
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delivery_dining),
          onPressed: () => _launchDeliveryApp(restaurant),
        ),
        onTap: () => _launchDeliveryApp(restaurant),
      ),
    );
  }

  /// 배달앱으로 이동합니다.
  Future<void> _launchDeliveryApp(KakaoPlace restaurant) async {
    try {
      // 배달앱 선택 다이얼로그 표시
      final selectedApp = await _showDeliveryAppDialog();
      if (selectedApp == null) return;

      String url;
      switch (selectedApp) {
        case 'baemin':
          // 배민: 앱 열기
          url = 'baemin://';
          break;
        case 'yogiyo':
          // 요기요: 앱 열기
          url = 'yogiyo://';
          break;
        case 'coupang_eats':
          // 쿠팡이츠: 앱 열기
          url = 'coupangeats://';
          break;
        case 'kakao_map':
          // 카카오맵: 앱 내에서 직접 위치 표시 (웹 리디렉션 방지)
          url = 'kakaomap://look?p=${restaurant.y},${restaurant.x}&app=1';
          break;
        default:
          return;
      }

      // 배달앱의 경우 바로 웹으로 이동 (URL 스킴이 불안정하므로)
      if (selectedApp == 'kakao_map') {
        // 카카오맵만 앱으로 시도
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          await _launchWebFallback(restaurant, selectedApp);
        }
      } else {
        // 배달앱은 바로 웹으로 이동
        await _launchWebFallback(restaurant, selectedApp);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('앱을 열 수 없습니다: $e')));
      }
    }
  }

  /// 배달앱 선택 다이얼로그
  Future<String?> _showDeliveryAppDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('앱 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDeliveryAppOption('baemin', '배민', '🍱'),
            _buildDeliveryAppOption('yogiyo', '요기요', '🍜'),
            _buildDeliveryAppOption('coupang_eats', '쿠팡이츠', '📦'),
            _buildDeliveryAppOption('kakao_map', '카카오맵', '🗺️'),
          ],
        ),
      ),
    );
  }

  /// 배달앱 옵션 위젯
  Widget _buildDeliveryAppOption(String value, String name, String emoji) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
      title: Text(name),
      onTap: () => Navigator.of(context).pop(value),
    );
  }

  /// 웹 폴백 (앱이 없을 때)
  Future<void> _launchWebFallback(KakaoPlace restaurant, String app) async {
    String webUrl;
    switch (app) {
      case 'baemin':
        webUrl = 'https://www.baemin.com/';
        break;
      case 'yogiyo':
        webUrl = 'https://www.yogiyo.co.kr/';
        break;
      case 'coupang_eats':
        webUrl = 'https://www.coupangeats.com/';
        break;
      case 'kakao_map':
        webUrl =
            'https://map.kakao.com/link/map/${restaurant.placeName},${restaurant.y},${restaurant.x}';
        break;
      default:
        return;
    }

    try {
      await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('웹페이지를 열 수 없습니다: $e')));
      }
    }
  }
}
