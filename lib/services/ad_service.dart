import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/config/security_config.dart';

// 1. Define the state for the ad service
class AdState {
  final RewardedAd? rewardedAd;
  final bool isAdLoaded;
  final bool isAdShowing;

  AdState({this.rewardedAd, this.isAdLoaded = false, this.isAdShowing = false});

  AdState copyWith({
    RewardedAd? rewardedAd,
    bool? isAdLoaded,
    bool? isAdShowing,
  }) {
    return AdState(
      rewardedAd: rewardedAd, // No null check, allow setting to null
      isAdLoaded: isAdLoaded ?? this.isAdLoaded,
      isAdShowing: isAdShowing ?? this.isAdShowing,
    );
  }
}

// 2. Create the StateNotifier
class AdService extends StateNotifier<AdState> {
  Completer<bool>? _adCompleter;
  bool _rewardReceived = false; // 보상 수령 상태 추가

  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _retryTimer;

  AdService() : super(AdState()) {
    loadAd();
  }

  Future<void> loadAd() async {
    if (state.isAdLoaded || state.isAdShowing) return;

    debugPrint('광고 로딩 시작... (시도: ${_retryCount + 1})');

    await RewardedAd.load(
      adUnitId: SecurityConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('광고 로딩 성공');
          _retryCount = 0; // 성공 시 재시도 카운트 초기화
          _retryTimer?.cancel();
          _configureAdCallbacks(ad);
          state = state.copyWith(rewardedAd: ad, isAdLoaded: true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('광고 로딩 실패: $error');
          state = state.copyWith(rewardedAd: null, isAdLoaded: false);
          _scheduleRetry();
        },
      ),
    );
  }

  void _scheduleRetry() {
    if (_retryCount >= _maxRetries) {
      debugPrint('최대 재시도 횟수 초과, 로딩 중단');
      return;
    }

    final delay = Duration(seconds: 2 * (1 << _retryCount)); // 2, 4, 8초...
    debugPrint('${delay.inSeconds}초 후 광고 로딩 재시도 예정...');

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryCount++;
      loadAd();
    });
  }

  void _configureAdCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('광고 표시 시작');
        state = state.copyWith(isAdShowing: true);
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('광고 닫힘 - 보상 상태: $_rewardReceived');
        ad.dispose();
        state = state.copyWith(
          rewardedAd: null,
          isAdLoaded: false,
          isAdShowing: false,
        );

        // 보상 수령 여부에 따라 결과 전달
        _adCompleter?.complete(_rewardReceived);
        _adCompleter = null;
        _rewardReceived = false; // 상태 초기화

        // 다음 광고 미리 로드
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('광고 표시 실패: $error');
        ad.dispose();
        state = state.copyWith(
          rewardedAd: null,
          isAdLoaded: false,
          isAdShowing: false,
        );

        // 실패했음을 알림
        _adCompleter?.complete(false);
        _adCompleter = null;
        _rewardReceived = false; // 상태 초기화

        // 다음 광고 미리 로드
        loadAd();
      },
    );
  }

  Future<bool> showAdWithRetry({
    required Function onUserEarnedReward,
    required Function(String) onAdFailedToLoad,
  }) async {
    // 이미 광고가 표시 중이면 기다림
    if (state.isAdShowing) {
      debugPrint('이미 광고가 표시 중입니다.');
      return false;
    }

    // 첫 시도 전 로딩 확인
    if (!state.isAdLoaded) {
      debugPrint('광고가 로드되지 않음, 로딩 시도...');
      await loadAd();
      // 로딩 대기 (최대 5초)
      for (int i = 0; i < 5; i++) {
        if (state.isAdLoaded) break;
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    for (int i = 0; i < 3; i++) {
      if (state.isAdLoaded && !state.isAdShowing) {
        debugPrint('광고 표시 시도 ${i + 1}번째');
        final success = await showAd(onUserEarnedReward: onUserEarnedReward);
        if (success) {
          return true;
        }
      }

      if (i < 2) {
        // 마지막 시도가 아닐 때만
        onAdFailedToLoad('광고를 불러오는 중입니다... (${i + 1}/3)');

        // 로딩이 안되어 있다면 다시 로드
        if (!state.isAdLoaded) {
          await loadAd();
        }

        // 로딩 대기 (최대 3초)
        for (int w = 0; w < 3; w++) {
          if (state.isAdLoaded) break;
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // 최종 시도
    if (state.isAdLoaded && !state.isAdShowing) {
      debugPrint('최종 광고 표시 시도');
      final success = await showAd(onUserEarnedReward: onUserEarnedReward);
      if (success) {
        return true;
      }
    }

    debugPrint('모든 광고 시도 실패');
    return false;
  }

  Future<bool> showAd({required Function onUserEarnedReward}) async {
    if (!state.isAdLoaded || state.isAdShowing) {
      debugPrint(
        '광고를 표시할 수 없습니다. 로드됨: ${state.isAdLoaded}, 표시중: ${state.isAdShowing}',
      );
      return false;
    }

    try {
      // 상태 초기화
      _rewardReceived = false;

      // Completer를 사용해서 광고가 완전히 끝날 때까지 기다림
      _adCompleter = Completer<bool>();

      await state.rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          debugPrint('보상 획득: ${reward.type}, ${reward.amount}');
          _rewardReceived = true;
          // 보상 콜백 실행
          onUserEarnedReward();
        },
      );

      // 광고가 완전히 끝날 때까지 기다림
      final success = await _adCompleter!.future;
      debugPrint('광고 완료 결과: $success');

      return success;
    } catch (e) {
      debugPrint('광고 표시 중 오류: $e');
      _adCompleter?.complete(false);
      _adCompleter = null;
      _rewardReceived = false;
      return false;
    }
  }

  @override
  void dispose() {
    _adCompleter?.complete(false);
    _adCompleter = null;
    _rewardReceived = false;
    state.rewardedAd?.dispose();
    super.dispose();
  }
}

// 3. Create the provider
final adServiceProvider = StateNotifierProvider<AdService, AdState>((ref) {
  return AdService();
});
