# 설계 문서

## 개요

음식명 입력 필드에서 발생하는 텍스트 중복 입력 버그를 수정합니다. 현재 문제는 TextEditingController의 `onChanged` 콜백이 Riverpod Provider를 업데이트하고, `ref.listen`이 다시 TextEditingController를 업데이트하는 순환 참조로 인해 발생합니다.

## 아키텍처

### 현재 문제점

```dart
// review_screen.dart의 현재 구조
TextFormField(
  controller: _foodNameController,
  onChanged: (text) => ref.read(reviewProvider.notifier).setFoodName(text), // 1. 사용자 입력 → Provider 업데이트
)

// build 메서드 내
ref.listen(reviewProvider.select((state) => state.foodName), (_, next) {
  if (_foodNameController.text != next) {
    _foodNameController.text = next; // 2. Provider 변경 → Controller 업데이트 → onChanged 트리거 → 무한 루프
  }
});
```

### 해결 방안

순환 업데이트를 방지하기 위해 다음 두 가지 접근 방식 중 하나를 사용합니다:

**방안 1: 업데이트 플래그 사용**

- `_isUpdatingFromProvider` 플래그를 사용하여 Provider로부터의 업데이트인지 사용자 입력인지 구분
- Provider 업데이트 시 플래그를 true로 설정하여 `onChanged` 콜백이 Provider를 다시 업데이트하지 않도록 함

**방안 2: TextEditingController.addListener 사용**

- `onChanged` 대신 `addListener`를 사용하여 더 세밀한 제어
- 리스너 내에서 조건부로 Provider 업데이트

**권장 방안: 방안 1 (업데이트 플래그)**

- 구현이 더 간단하고 명확함
- Flutter의 일반적인 패턴과 일치
- 디버깅이 용이함

## 컴포넌트 및 인터페이스

### 수정할 컴포넌트

1. **ReviewScreen (\_ReviewScreenState)**
   - `_isUpdatingFromProvider` 플래그 추가
   - `ref.listen` 콜백 수정
   - `onChanged` 콜백 수정

### 데이터 흐름

```
사용자 입력 → onChanged → Provider 업데이트 (플래그 체크)
                                ↓
                         ref.listen 감지
                                ↓
                    플래그 설정 → Controller 업데이트
                                ↓
                         onChanged 트리거
                                ↓
                    플래그 체크 → Provider 업데이트 스킵
```

## 데이터 모델

기존 데이터 모델 변경 없음. ReviewState와 ReviewNotifier는 그대로 유지됩니다.

## Correctness Properties

_A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees._

### Property 1: 단일 문자 표시

_For any_ 사용자 입력 문자, 텍스트 필드에 정확히 한 번만 표시되어야 한다
**Validates: Requirements 1.1**

### Property 2: 순환 업데이트 방지

_For any_ Controller 업데이트, Provider로부터의 업데이트인 경우 다시 Provider를 업데이트하지 않아야 한다
**Validates: Requirements 1.2, 2.1**

### Property 3: 외부 업데이트 반영

_For any_ Provider 상태 변경 (AI 생성 등), Controller가 새로운 값으로 올바르게 업데이트되어야 한다
**Validates: Requirements 1.3**

### Property 4: 커서 위치 유지

_For any_ 연속된 사용자 입력, 커서 위치가 입력된 텍스트의 끝에 유지되어야 한다
**Validates: Requirements 1.4**

### Property 5: 상태 보존

_For any_ 포커스 변경, 입력된 텍스트가 중복 없이 보존되어야 한다
**Validates: Requirements 1.5**

## 에러 처리

- Controller dispose 시 리스너 정리 확인
- 플래그 상태가 올바르게 리셋되는지 확인
- null 값 처리 (빈 문자열과 null 구분)

## 테스트 전략

### 단위 테스트

1. **텍스트 입력 테스트**

   - 단일 문자 입력 시 중복 없이 표시되는지 확인
   - 여러 문자 연속 입력 시 올바르게 표시되는지 확인

2. **상태 동기화 테스트**

   - Provider 상태 변경 시 Controller가 업데이트되는지 확인
   - Controller 변경 시 Provider가 업데이트되는지 확인
   - 순환 업데이트가 발생하지 않는지 확인

3. **AI 생성 테스트**
   - AI로 음식명 생성 시 텍스트 필드가 올바르게 업데이트되는지 확인
   - 생성 중 사용자가 입력하는 경우 처리 확인

### 통합 테스트

1. **UI 상호작용 테스트**
   - 실제 사용자 입력 시나리오 테스트
   - 포커스 변경 시나리오 테스트
   - AI 버튼 클릭 후 텍스트 업데이트 테스트

### 수동 테스트 시나리오

1. 음식명 필드에 "짜장면" 입력 → "짜장면"으로 표시되는지 확인
2. AI 버튼 클릭 → 생성된 음식명이 올바르게 표시되는지 확인
3. 음식명 입력 후 다른 필드로 포커스 이동 → 텍스트 보존 확인
4. 빠르게 연속 입력 → 모든 문자가 올바르게 표시되는지 확인

## 구현 세부사항

### 코드 변경

```dart
class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final TextEditingController _foodNameController = TextEditingController();
  bool _hasNavigatedToSelection = false;
  bool _isGeneratingFoodName = false;
  bool _isUpdatingFromProvider = false; // 새로 추가

  @override
  Widget build(BuildContext context) {
    // ... 기존 코드 ...

    // Provider 변경 감지 - 플래그 사용
    ref.listen(reviewProvider.select((state) => state.foodName), (_, next) {
      if (_foodNameController.text != next) {
        _isUpdatingFromProvider = true; // 플래그 설정
        _foodNameController.text = next;
        _isUpdatingFromProvider = false; // 플래그 해제
      }
    });

    // ... 기존 코드 ...
  }

  Widget _buildFoodNameInput(Responsive responsive) {
    return Container(
      // ... 기존 decoration ...
      child: TextFormField(
        controller: _foodNameController,
        onChanged: (text) {
          // 플래그 체크 - Provider 업데이트로부터 온 경우 스킵
          if (!_isUpdatingFromProvider) {
            ref.read(reviewProvider.notifier).setFoodName(text);
          }
        },
        // ... 기존 설정 ...
      ),
    );
  }
}
```

### 주의사항

1. `_isUpdatingFromProvider` 플래그는 동기적으로 설정/해제되어야 함
2. 플래그 설정 후 반드시 해제해야 메모리 누수 방지
3. AI 생성 시에도 동일한 메커니즘 적용
4. dispose 시 Controller 정리 확인

## 성능 고려사항

- 플래그 체크는 O(1) 연산으로 성능 영향 없음
- ref.listen은 이미 최적화되어 있어 추가 오버헤드 없음
- TextEditingController 업데이트는 Flutter 프레임워크에서 최적화됨

## 호환성

- Flutter 3.x 이상
- Riverpod 2.x 이상
- 기존 코드와 100% 호환
- 다른 화면이나 컴포넌트에 영향 없음
