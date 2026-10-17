# 2026-10-17 개선 후보 및 개발 검증

## 저장소와 로그인 확인

- 저장소: `JongHyun070105/how-about-this`, 작업 경로와 origin 일치.
- GitHub CLI: `JongHyun070105` 활성 계정과 저장소 push 권한을 읽기 전용으로 확인했다.
- Wrangler `whoami`: 미인증. Firebase CLI `login:list`: 승인된 계정 없음. 브라우저 로그인 여부와 앱 사용자 로그인 상태는 이 결과로 판단할 수 없다.
- 시작 시 `main`은 `ce22d5f`이고 깨끗했다. 요청대로 `develop`으로 전환하고, 기존 `860ff99`에서 `ce22d5f`로 fast-forward하여 어제 main에 반영된 수정사항을 보존했다.

## 우선순위와 이번 수정

1. **출시 노트 생성의 잘못된 AI 응답 처리 — 수정 완료.** JSON에 `ko`, `en` 키만 있으면 숫자·배열·객체도 반환했다. 참으로 평가되는 숫자 등은 `main()`의 fallback 조건을 통과한 후 문자열 슬라이싱에서 실패할 수 있었다. 두 언어 모두 비어 있지 않은 문자열일 때만 채택하며, 그 외에는 기존 로컬 fallback으로 두 언어를 함께 대체한다. 외부 AI 호출 없이 HTTP 응답을 모사해 검증했다.
2. **음식명 유니코드 길이 제한 — 후속 재현 대상.** `lib/services/prompt_builder.dart`의 `substring(0, 100)`은 UTF-16 경계에서 이모지를 분리할 가능성이 있다. 제어 문자 제거도 현재 CR/LF/TAB에 한정된다. 이번에는 제품 동작을 바꾸지 않았으며, 실제 프롬프트·직렬화 경로의 회귀 테스트 후 별도 수정할 후보로 남긴다.
3. **영어 출시 노트 출력 — 정책 확인 대상.** 스크립트는 영어 문구도 생성하지만 파일 출력은 주 등록 언어인 `ko-KR`에 한정된다. `en-US`가 Play Console에 등록돼 있는지 확인하지 않았으므로 새 언어 출력을 임의로 추가하지 않았다.
4. **운영 App Check 전환 — 별도 운영 검증 대상.** 어제 문서에 기록된 monitor 정책을 유지했다. 정상 기기 검증 성공률과 구버전 보급률 확인 없이 enforce로 전환하지 않았다.
5. **추천 프롬프트 규칙·예시 충돌 — 후속 개선 후보.** Gemini 검토가 지적한 `_getCategoryRule`의 금지 메뉴와 `_getCategoryExamples`의 예시 메뉴 중복을 현재 소스에서 확인했다. 중식의 탕수육, 일식의 사시미, 양식의 감바스가 해당한다. 실제 모델 출력 영향은 측정하지 않았으며, 기존 메뉴 정책을 기준으로 예시를 정렬하는 회귀 테스트를 후속 작업으로 권장한다.

## 회귀 검증

- Python helper: 5개 테스트 통과. 잘못된 값 7종을 각 언어에 적용한 14개 사례, 최상위 배열, 실제 `main()`의 `42.txt`·`default.txt` fallback 저장, 기존 정상 응답 및 비밀 로그 방지 테스트를 포함한다.
- 수정 전 새 테스트에서 14개 사례가 실패함을 확인한 후 수정했다. 로컬 실패 로그 `.tools/release-notes-red-20261017.log`와 성공 로그 `.tools/release-notes-green-20261017.log`를 보존했다.
- Worker: `npm test --prefix cloudflare-worker` 31개 통과.
- 실제 local workerd + SQLite: 만료 cleanup, 지연 알람, 동시 한도 3개 허용/17개 차단 통과.
- Flutter: 전체 281개 테스트 통과. `flutter analyze --no-fatal-infos`: 문제 없음.
- 저장소 hygiene 검사 및 `git diff --check` 통과.
- Dart format: `lib`, `test` 173개 파일 확인, 변경 필요 없음.

## 독립 검토와 한계

초기 `orch-parallel`은 Gemini와 AGY Sonnet에 읽기 전용 검토를 요청했다. 두 검토 모두 후보를 반환했으나 실행 중 MAIN의 fast-forward로 checkout 변경 감지에 실패했다. 수집 결과는 BLOCKED이며 검증된 완료 결과로 간주하지 않는다. 영어 출력, 문자열 자르기, 추천 예시 충돌 후보는 MAIN이 현재 소스에서 재확인했으며, 실제 사용자 영향은 위에 적은 후속 검증이 필요하다. 다음 검토에서는 브랜치 동기화를 먼저 끝내 HEAD를 고정해야 한다.

별도 Claude Sonnet 최종 검토는 수정한 두 Python 파일을 검토하고 차단 사유 없음과 5개 테스트 통과를 보고했다. MAIN도 같은 테스트를 직접 실행해 확인했다. 이 작업은 전체 저장소 보안 감사가 아니며 운영 배포·외부 AI 호출·클라우드 설정 변경은 수행하지 않았다.
