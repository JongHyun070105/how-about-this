# ReviewAI Cloudflare Workers API Proxy

Cloudflare Workers를 사용한 ReviewAI API 프록시 서버입니다.

## 🚀 배포 방법

### 1. Cloudflare 계정 준비

1. [Cloudflare Dashboard](https://dash.cloudflare.com/)에서 계정 생성/로그인
2. Workers & Pages 메뉴로 이동

### 2. Wrangler CLI 설치

```bash
cd cloudflare-worker
npm install
```

### 3. Wrangler 로그인

```bash
npx wrangler login
```

브라우저가 열리면 Cloudflare 계정으로 로그인하세요.

### 4. 저장소 바인딩 확인

- 요청 제한은 `RateLimiter` Durable Object가 원자적으로 처리합니다. `wrangler.toml`의 migration이 최초 배포 시 클래스를 생성하므로 별도 KV 생성이 필요하지 않습니다.
- 응답 캐시는 `API_CACHE` KV를 사용합니다. 새 환경을 만들 때만 해당 namespace를 생성하고 `wrangler.toml`에 ID를 등록하세요.

### 5. 환경 변수 설정 (Secret)

#### GEMINI_API_KEY 설정

```bash
npx wrangler secret put GEMINI_API_KEY
```

프롬프트가 나오면 Gemini API 키를 입력하세요.

#### JWT_SECRET 설정

```bash
npx wrangler secret put JWT_SECRET
```

프롬프트가 나오면 랜덤 문자열을 입력하세요 (예: 64자 이상의 랜덤 문자열).

랜덤 문자열 생성 (Node.js):

```bash
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

### 6. 배포

```bash
npm run deploy
```

프로덕션 배포 전에는 `npm test`와 Wrangler dry-run을 먼저 실행하세요.

배포가 완료되면 다음과 같은 URL이 제공됩니다:

```
https://reviewai-api-proxy.YOUR_SUBDOMAIN.workers.dev
```

### 7. Flutter 앱 설정 업데이트

Flutter 앱의 `lib/config/api_config.dart` 파일에서 `proxyUrl`을 업데이트하세요:

```dart
class ApiConfig {
  static const String proxyUrl = 'https://reviewai-api-proxy.YOUR_SUBDOMAIN.workers.dev';
  static const Duration timeout = Duration(seconds: 30);
}
```

## 🧪 테스트

### 헬스 체크

```bash
curl https://reviewai-api-proxy.YOUR_SUBDOMAIN.workers.dev/health
```

### 토큰 발급 테스트

프로덕션 앱은 Firebase App Check 토큰을 `X-Firebase-AppCheck` 헤더로 전송합니다. 로컬 curl 요청은 Worker가 `monitor` 모드일 때만 허용됩니다.

```bash
curl -X POST https://reviewai-api-proxy.YOUR_SUBDOMAIN.workers.dev/api/auth/token \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"test-device","appVersion":"1.0.5","deviceInfo":"test"}'
```

## 📊 모니터링

Cloudflare Dashboard의 Workers > reviewai-api-proxy에서 다음을 확인할 수 있습니다:

- 요청 횟수
- 성공/실패율
- 응답 시간
- 에러 로그

## 💰 비용

- **무료 플랜**: 100,000 요청/일
- **유료 플랜**: $5/월 (10,000,000 요청)

현재 앱 규모에서는 무료 플랜으로 충분합니다!

## 🔧 로컬 개발

```bash
npm run dev
```

로컬에서 테스트할 수 있습니다 (http://localhost:8787).

## ⚡ 특징

- ✅ **Cold Start 0초**: 전세계 엣지 네트워크에서 즉시 응답
- ✅ **JWT 인증**: 동적 토큰 기반 보안
- ✅ **App Check**: Play Integrity/App Attest 기반 앱 진위 검증
- ✅ **Rate Limiting**: Durable Object 트랜잭션 기반 원자적 요청 제한
- ✅ **글로벌 배포**: 전세계 어디서나 빠른 응답
- ✅ **무료**: 하루 10만 요청까지 무료

## 🔒 보안

- API 키는 환경 변수(Secret)로 안전하게 저장
- JWT 토큰 기반 인증
- Firebase App Check로 정식 앱 인스턴스 확인
- 엔드포인트별 Rate Limiting으로 남용 방지
- CORS 설정으로 접근 제어

### App Check 단계적 적용

1. Firebase Console의 App Check에서 Android 앱은 Play Integrity, iOS 앱은 App Attest를 등록합니다.
2. 먼저 `APP_CHECK_ENFORCEMENT = "monitor"`로 배포해 `app_check_monitor` 로그의 `missing`/`invalid` 비율을 확인합니다.
3. 정상 앱 버전 보급과 iOS 서명 프로파일의 App Attest capability 적용을 확인합니다.
4. 미검증 요청이 충분히 감소한 후 별도 검토 PR에서 `APP_CHECK_ENFORCEMENT = "enforce"`로 전환합니다.

디버그 토큰은 개발자 로컬 환경과 Firebase Console에만 등록하고 저장소에 커밋하지 마세요. `monitor` 모드는 전환 중 장애를 방지하기 위한 상태이며, 미검증 토큰 발급도 임시로 허용합니다. 이때 새로 발급되는 미검증 refresh token은 24시간으로 제한됩니다(검증 성공 시 7일).

## 📝 참고

- [Cloudflare Workers 문서](https://developers.cloudflare.com/workers/)
- [Wrangler CLI 문서](https://developers.cloudflare.com/workers/wrangler/)
