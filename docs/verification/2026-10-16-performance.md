# 2026-10-16 보안 점검 및 성능 개선 검증

기준 커밋: `860ff990d9813ff27d713c4159e8248d91b00340`. 변경은 기존 API 형식과 App Check 단계적 적용 정책을 유지한다. 두 독립 검토(Claude Code Sonnet, AGY Sonnet)의 주장은 MAIN이 소스와 테스트로 재검증했다. Worker 7개 소스 파일 전체, 주요 Flutter 인증·저장·이미지·통계 서비스, CI 배포 경로를 검토했다. 전체 349개 추적 파일에 대한 완전한 보안 감사나 실서비스 침투 테스트는 아니다.

## 측정 결과

Apple M1 Pro / macOS arm64 / Node v26.11.1. 각 구현 500회 예열 후, 5,000회 JWT 검증을 7세트 수행했다. 실행 순서를 번갈아 측정했으며 결과는 중앙값이다. 매번 실제 서명 검증과 claim 검사를 수행하고 반환값을 확인했다.

| 지표 | 변경 전 | 변경 후 | 변화 |
|---|---:|---:|---:|
| JWT 검증 5,000회 중앙값 | 97.651ms | 73.984ms | 소요시간 24.24% 감소, 처리량 1.32배 |
| JWT 서명 1회 + 검증 1,000회 키 import | 1,001회 | 1회 | 99.90% 감소 |
| 동일 창 요청 1,000회 cleanup 알람 설정 | 1,000회 | 1회 | 99.90% 감소 |
| 동일 요청의 저장소 쓰기 메서드 호출 합계 | 2,000회 | 1,001회 | 49.95% 감소 |

원시 표본은 [performance-results.json](performance-results.json)에 보관한다. JWT는 실제 Web Crypto 연산을 측정했다. 저장소 수치는 production `RateLimiter`를 실행하는 counting double에서 `put`/`setAlarm` 호출을 센 값이다. 실제 Cloudflare 청구 단위, 네트워크 지연, 앱 화면 FPS의 개선율로 해석하면 안 된다. 전체 요청 시간에는 외부 AI·네트워크·Durable Object 지연이 포함되므로 이 수치를 그대로 적용할 수 없다.

재현:

```sh
node cloudflare-worker/benchmark/hot-paths.js 860ff990d9813ff27d713c4159e8248d91b00340
npm test --prefix cloudflare-worker
npm run test:runtime --prefix cloudflare-worker
```

벤치마크는 기준 Git 소스와 현재 소스를 같은 프로세스에서 비교한다. 실제 API 호출·클라우드 쓰기·운영 키는 사용하지 않는다. 실행 중인 하드웨어와 Node 버전에 따라 시간은 달라지며 CI에서는 시간 임계값으로 PASS를 강제하지 않는다.

## 적용한 변경

- JWT HMAC 키의 import Promise를 isolate 안에서 1개만 재사용한다. 동시 요청 중복 import를 줄이고, secret 변경 시 교체하며 import 실패는 다음 요청에서 재시도한다. 토큰 검증 자체는 캐시하지 않는다.
- 레이트리미터의 창 생성과 알람 예약을 같은 트랜잭션에서 처리하고, 허용된 매 요청마다 같은 알람을 재설정하지 않는다.
- 오래 지연된 알람이 새 창의 카운터를 지우던 문제를 수정했다. 만료 시각을 확인해 활성 창은 유지하고 정리 알람을 다시 예약한다. `deleteAll()`은 실제 Workers에서 명시적 트랜잭션 안에 허용되지 않아, storage input gate가 보장하는 read/cleanup 순서를 사용한다. [Cloudflare storage API](https://developers.cloudflare.com/durable-objects/api/legacy-kv-storage-api/), [알람 지연 및 재시도](https://developers.cloudflare.com/durable-objects/api/alarms/).
- Kakao category code를 허용 목록으로 검증하고, 캐시 키를 URLSearchParams로 구성한다. Kakao/날씨의 검증된 숫자를 캐시와 upstream에서 일관되게 사용한다. 숫자 별칭으로 다른 캐시 키를 만들거나 서로 다른 좌표로 해석되는 문제를 줄인다.
- Wrangler `4.136.2 → 4.151.1`, Firebase CLI `15.30.2 → 15.34.0` 및 호환되는 전이 의존성을 갱신했다. 기존 OpenTelemetry/gaxios/qs 호환 override는 유지했다.

## 의존성 보안 검사

동일 날짜의 `npm audit --json` 비교이며, 패키지 경고 수는 독립 취약점 수나 실서비스 악용 가능성을 의미하지 않는다.

| 범위 | 변경 전 | 변경 후 |
|---|---|---|
| Worker 개발/배포 도구 | high 4 | 0 |
| CI 도구 | critical 1, high 10, moderate 4 (총 15) | high 3 |

CI의 남은 3건은 `firebase-tools → chokidar → braces@3.0.3`에 전파되는 동일 [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm) 경고다. 현 검사에서 패치 가능한 최신 braces 버전이 없으며 npm의 제안은 Firebase CLI `6.8.0`으로의 major downgrade다. 정상 App Distribution 동작을 깨뜨리는 downgrade나 검사를 무시하는 override는 적용하지 않았다. 이 저장소의 배포 경로는 정해진 appdistribution CLI 명령을 사용하며 외부 사용자의 glob 패턴을 CLI에 전달하는 경로는 확인되지 않았다. Emulator/watch 또는 외부 패턴 처리 기능을 추가할 때 재검토해야 한다.

## 남은 운영 보안 항목

`wrangler.toml`의 production App Check는 `monitor` 상태다. 미검증 앱도 device metadata로 JWT를 발급받고 IP별 한도 내에서 유료 API를 사용할 수 있다. IP를 분산한 남용은 앱 진위 검증으로 차단되지 않는다. 두 검토에서 공통으로 확인했고 소스와 기존 monitor/enforce 테스트로 검증했다. 실제 배포 설정·App Check 성공률·기존 앱 버전 보급률은 확인하지 않았다. 기존 사용자를 차단할 수 있으므로 이번 변경에서 `enforce`로 강제하지 않았다. 정상 기기의 Play Integrity/App Attest 성공률과 앱 버전 보급을 확인한 후 별도 운영 전환이 필요하다.

Firebase API 키와 AdMob ID는 공개 클라이언트 식별자이며 그 자체로 서버 비밀 키 노출로 판단하지 않았다. Google Cloud의 키 제한, 운영 JWT secret 강도, WAF 및 비용 한도는 소스만으로 확인할 수 없다. 실제 운영 키를 읽거나 변경하지 않았다.

## 검증

- Flutter 3.35.1 / Dart 3.9.0: `flutter test` 281개 통과, `flutter analyze --no-fatal-infos` 문제 없음.
- Dart 포맷: 175개 파일, 변경 필요 없음.
- Worker Node 26 및 CI와 같은 Node 22: 보안/회귀 테스트 31개 통과.
- 실제 local workerd + SQLite: 만료 cleanup, 지연된 알람 후 활성 카운터 유지, 동시 20개 요청에서 남은 3개만 허용/17개 거절 확인. 재현 스크립트를 CI QA에 추가했다.
- Wrangler production dry-run 번들링 통과. 클라우드 배포 호출 없음.
- Firebase CLI 15.34.0: Node 22에서 version 및 App Distribution 명령 도움말 확인.
- 저장소 hygiene 검사, CI Python helper 테스트 2개, `git diff --check` 통과.

회귀 테스트는 개선 전 키 import 40회, 알람 중복 설정, 활성 창 삭제, 잘못된 카테고리 허용, 좌표 해석 불일치로 실패하는 것을 먼저 확인한 뒤 수정했다. 실제 런타임 검증에서 `deleteAll()`의 트랜잭션 제약을 발견해 수정하고 재검증했다. 최종 GitHub 커밋 SHA와 CI/병합 결과는 PR 및 최종 작업 보고에서 확인할 수 있다.
