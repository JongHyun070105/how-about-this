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

### 4. KV Namespace 생성 (Rate Limiting용)

```bash
npx wrangler kv:namespace create RATE_LIMIT
```

출력된 `id`를 복사해서 `wrangler.toml` 파일의 주석 처리된 부분에 넣으세요:

```toml
[[kv_namespaces]]
binding = "RATE_LIMIT"
id = "여기에_복사한_ID_붙여넣기"
```

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
- ✅ **Rate Limiting**: KV를 사용한 분산 Rate Limiting
- ✅ **글로벌 배포**: 전세계 어디서나 빠른 응답
- ✅ **무료**: 하루 10만 요청까지 무료

## 🔒 보안

- API 키는 환경 변수(Secret)로 안전하게 저장
- JWT 토큰 기반 인증
- Rate Limiting으로 남용 방지
- CORS 설정으로 접근 제어

## 📝 참고

- [Cloudflare Workers 문서](https://developers.cloudflare.com/workers/)
- [Wrangler CLI 문서](https://developers.cloudflare.com/workers/wrangler/)

