import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:review_ai/domain/usecases/generate_review_usecase.dart';
import 'package:review_ai/models/review_state.dart';
import 'package:review_ai/presentation/providers/dependency_injection.dart';
import 'package:review_ai/services/ad_service.dart';
import 'package:review_ai/viewmodels/review_viewmodel.dart';

import 'review_viewmodel_test.mocks.dart';

@GenerateMocks([GenerateReviewUseCase, AdService])
void main() {
  late MockGenerateReviewUseCase mockGenerateReviewUseCase;
  late MockAdService mockAdService;
  late ProviderContainer container;

  setUp(() {
    mockGenerateReviewUseCase = MockGenerateReviewUseCase();
    mockAdService = MockAdService();

    container = ProviderContainer(
      overrides: [
        generateReviewUseCaseProvider.overrideWithValue(
          mockGenerateReviewUseCase,
        ),
        // AdService는 StateNotifier이므로 notifier를 override해야 하지만,
        // ReviewViewModel은 AdService 인스턴스를 주입받음.
        // 하지만 reviewViewModelProvider 정의에서 ref.watch(adServiceProvider.notifier)를 사용함.
        // 따라서 adServiceProvider.notifier를 override 해야 함.
        // AdService는 StateNotifier<AdState>일 것임.
        // MockAdService가 StateNotifier를 상속받지 않으면 문제될 수 있음.
        // AdService 정의를 확인해야 함. 만약 AdService가 StateNotifier라면 MockAdService도 그래야 함.
        // 하지만 Mockito로 생성된 Mock은 기본적으로 mixin이므로 extends StateNotifier를 하지 않음.
        // 따라서 MockAdService를 StateNotifierProvider에 넣으려면 타입 불일치가 발생할 수 있음.
        // 일단 ReviewViewModel 생성자에 직접 주입하는 방식으로 테스트를 구성하는 것이 안전함.
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('Initial state is correct', () {
    // ReviewViewModel을 직접 생성하여 테스트 (Provider override 복잡성 회피)
    // Ref는 Mock 또는 Fake가 필요하지만, ReviewViewModel 내부에서 ref.read를 사용하므로
    // ProviderContainer를 통해 생성된 ref를 사용해야 함.

    // 따라서 reviewViewModelProvider를 override하여 Mock 의존성을 주입
    final container = ProviderContainer(
      overrides: [
        reviewViewModelProvider.overrideWith((ref) {
          return ReviewViewModel(ref, mockGenerateReviewUseCase);
        }),
      ],
    );

    final viewModel = container.read(reviewViewModelProvider);
    expect(viewModel, const ReviewState.initial());
  });
}
