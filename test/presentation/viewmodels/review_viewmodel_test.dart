import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart' show Mock;
import 'package:review_ai/domain/usecases/generate_review_usecase.dart';
import 'package:review_ai/presentation/providers/dependency_injection.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';
import 'package:review_ai/presentation/viewmodels/review_viewmodel.dart';

class _GenerateReviewUseCaseFake extends Mock
    implements GenerateReviewUseCase {}

void main() {
  testWidgets('공유 리뷰 상태가 로딩 중이면 중복 생성 요청을 무시한다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generateReviewUseCaseProvider.overrideWith(
          (ref) => _GenerateReviewUseCaseFake(),
        ),
      ],
    );
    BuildContext? buildContext;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              buildContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );

    container.read(reviewProvider.notifier).setLoading(true);
    final viewModel = container.read(reviewViewModelProvider.notifier);

    await viewModel.generateReviews(buildContext!);

    expect(container.read(reviewProvider).isLoading, isTrue);
    container.dispose();
  });
}
