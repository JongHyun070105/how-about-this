import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:review_ai/data/models/location_models.dart';

/// 배달앱/지도앱 실행 유틸리티
///
/// 배달앱 선택 및 외부 앱 실행 로직을 캡슐화합니다.
abstract class DeliveryAppLauncher {
  @visibleForTesting
  static void Function(ClipboardData data)? mockClipboardSetter;

  @visibleForTesting
  static Future<bool> Function(Uri url)? mockCanLaunchUrl;

  @visibleForTesting
  static Future<bool> Function(Uri url, LaunchMode mode)? mockUrlLauncher;

  static Future<void> _setClipboardData(ClipboardData data) async {
    if (mockClipboardSetter != null) {
      mockClipboardSetter!(data);
    } else {
      await Clipboard.setData(data);
    }
  }

  static Future<bool> _canLaunch(Uri url) async {
    if (mockCanLaunchUrl != null) {
      return mockCanLaunchUrl!(url);
    }
    return canLaunchUrl(url);
  }

  static Future<bool> _launch(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    if (mockUrlLauncher != null) {
      return mockUrlLauncher!(url, mode);
    }
    return launchUrl(url, mode: mode);
  }

  /// 배달앱 선택 후 실행 진입점
  static Future<void> launch(
    BuildContext context,
    KakaoPlace restaurant, {
    required double? currentLat,
    required double? currentLng,
    required Future<String?> Function() showDeliveryAppDialog,
  }) async {
    try {
      final selectedApp = await showDeliveryAppDialog();
      if (selectedApp == null) return;

      switch (selectedApp) {
        case 'baemin':
        case 'yogiyo':
        case 'coupang_eats':
          if (context.mounted) {
            await _launchOtherDeliveryApp(context, restaurant, selectedApp);
          }
          break;
        case 'kakao_map':
          if (context.mounted) {
            await _launchKakaoMap(
              context,
              restaurant,
              currentLat: currentLat,
              currentLng: currentLng,
            );
          }
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('앱을 실행하는 중 오류가 발생했습니다.')));
      }
    }
  }

  /// 배민/요기요/쿠팡이츠 실행
  static Future<void> _launchOtherDeliveryApp(
    BuildContext context,
    KakaoPlace restaurant,
    String appName,
  ) async {
    await _setClipboardData(ClipboardData(text: restaurant.placeName));

    if (!context.mounted) return;

    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('📋 복사 완료!'),
        content: Text(
          '"${restaurant.placeName}"이(가)\n클립보드에 복사되었습니다.\n\n'
          '앱에서 검색창에 붙여넣기하여\n주문하세요!',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('앱 열기'),
          ),
        ],
      ),
    );

    if (shouldProceed != true || !context.mounted) return;

    final appInfo = _getDeliveryAppInfo(appName);
    if (appInfo == null) return;

    bool launchSuccess = false;
    for (final urlScheme in appInfo.urlSchemes) {
      try {
        final uri = Uri.parse(urlScheme);
        if (await _canLaunch(uri)) {
          launchSuccess = await _launch(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (launchSuccess) break;
        }
      } catch (_) {
        continue;
      }
    }

    if (!launchSuccess && context.mounted) {
      await _promptOpenStore(context, appInfo, appName);
    }
  }

  static Future<void> _promptOpenStore(
    BuildContext context,
    _DeliveryAppInfo appInfo,
    String appName,
  ) async {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final storeName = isIOS ? 'App Store' : 'Play Store';

    final shouldOpenStore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${appInfo.displayName} 앱'),
        content: Text(
          '${appInfo.displayName} 앱을 실행할 수 없습니다.\n\n'
          '$storeName에서 앱을 설치 또는 업데이트하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('$storeName 열기'),
          ),
        ],
      ),
    );

    if (shouldOpenStore != true || !context.mounted) return;

    final storeUrl = isIOS
        ? 'https://apps.apple.com/kr/app/id${appInfo.appStoreId}'
        : 'market://details?id=${appInfo.packageName}';

    try {
      await _launch(Uri.parse(storeUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isIOS ? 'App Store를 열 수 없습니다' : 'Play Store를 열 수 없습니다',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 카카오맵 실행 (길찾기 또는 장소 보기)
  static Future<void> _launchKakaoMap(
    BuildContext context,
    KakaoPlace restaurant, {
    required double? currentLat,
    required double? currentLng,
  }) async {
    try {
      final String appScheme;
      final String webUrl;

      if (currentLat != null && currentLng != null) {
        final startName = Uri.encodeComponent('내 위치');
        final endName = Uri.encodeComponent(restaurant.placeName);
        appScheme =
            'kakaomap://route?'
            'sp=$currentLat,$currentLng&'
            'ep=${restaurant.y},${restaurant.x}&'
            'sn=$startName&'
            'en=$endName';
        webUrl =
            'https://map.kakao.com/link/to/'
            '$endName,${restaurant.y},${restaurant.x}/'
            'from/$startName,$currentLat,$currentLng';
      } else {
        final endName = Uri.encodeComponent(restaurant.placeName);
        appScheme = 'kakaomap://look?p=${restaurant.y},${restaurant.x}&app=1';
        webUrl =
            'https://map.kakao.com/link/map/'
            '$endName,${restaurant.y},${restaurant.x}';
      }

      final uri = Uri.parse(appScheme);
      if (await _canLaunch(uri)) {
        await _launch(uri, mode: LaunchMode.externalApplication);
      } else {
        await _launch(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카카오맵을 실행할 수 없습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static _DeliveryAppInfo? _getDeliveryAppInfo(String appName) {
    const apps = {
      'baemin': _DeliveryAppInfo(
        displayName: '배민',
        urlSchemes: ['baemin://'],
        packageName: 'com.sampleapp',
        appStoreId: '378084485',
      ),
      'yogiyo': _DeliveryAppInfo(
        displayName: '요기요',
        urlSchemes: ['yogiyoapp://open'],
        packageName: 'com.fineapp.yogiyo',
        appStoreId: '543831532',
      ),
      'coupang_eats': _DeliveryAppInfo(
        displayName: '쿠팡이츠',
        urlSchemes: ['coupangeats://'],
        packageName: 'com.coupang.mobile.eats',
        appStoreId: '1445504255',
      ),
    };
    return apps[appName];
  }
}

class _DeliveryAppInfo {
  final String displayName;
  final List<String> urlSchemes;
  final String packageName;
  final String appStoreId;

  const _DeliveryAppInfo({
    required this.displayName,
    required this.urlSchemes,
    required this.packageName,
    required this.appStoreId,
  });
}
