# 이거어때?

## 개요

이거어때?는 이미지, 음식명, 별점을 입력받아 Gemini API(gemini-2.5-flash-lite)를 통해 음식 리뷰를 3개 생성하고, 사용자가 선택하여 복사할 수 있는 Flutter 애플리케이션입니다. 이 앱은 사용자에게 편리하고 다양한 리뷰 옵션을 제공하여 음식 리뷰 작성 과정을 간소화합니다.

## 주요 기능

### 🤖 AI 기반 리뷰 작성
- **이미지 업로드**: 음식 사진을 쉽게 업로드할 수 있습니다.
- **음식 정보 입력**: 음식사진과 별점을 입력하여 리뷰 생성의 기반을 마련합니다.
- **Gemini API 연동**: Gemini API를 활용하여 입력된 정보를 바탕으로 3가지의 독창적인 음식 리뷰를 생성합니다.
- **리뷰 선택 및 복사**: 생성된 리뷰 중 마음에 드는 것을 선택하여 간편하게 복사할 수 있습니다.
- **리뷰 기록**: 생성된 리뷰들을 기록하여 다시 볼 수 있습니다.

### 🍽️ 오늘의 음식 추천
- **카테고리별 추천**: 한식, 중식, 일식, 양식, 분식 등 다양한 카테고리별 음식 추천
- **개인화 추천 시스템**: 사용자의 식사 기록과 선호도를 분석하여 맞춤 추천 제공
- **날씨 기반 추천**: 실시간 날씨 정보를 활용한 스마트 추천 (비 오는 날 따뜻한 국물 요리, 맑은 날 냉면 등)
- **추천 사유 제공**: 각 음식 추천에 대한 구체적인 이유 설명
- **사용 통계**: 식습관 분석 및 통계 제공

### 📍 맛집 검색 및 배달 연동
- **위치 기반 검색**: 현재 위치를 기반으로 근처 음식점 자동 검색 (카카오 로컬 API 활용)
- **배달앱 연동**: 배민, 요기요, 쿠팡이츠 등 배달앱 바로 연결
- **카카오맵 길찾기**: 선택한 음식점까지 카카오맵 길찾기 기능
- **음식점 정보**: 거리, 주소, 전화번호, 카테고리 등 상세 정보 제공

### 🔒 보안 및 인증
- **JWT 기반 인증**: Cloudflare Workers를 통한 동적 토큰 관리
- **Rate Limiting**: 15분당 100회 요청 제한으로 과도한 API 호출 방지
- **안전한 토큰 저장**: flutter_secure_storage를 활용한 로컬 토큰 암호화 저장
- **서버 시간 동기화**: 시스템 시간 조작 방지를 위한 서버 시간 검증

### 📱 추가 기능
- **AdMob 광고 통합**: 배너 광고 및 리워드 광고 지원
- **일일 사용 제한**: 무료 사용자를 위한 합리적인 일일 추천 한도

## 기술 스택

### Frontend
- **프레임워크**: Flutter
- **언어**: Dart
- **상태 관리**: Riverpod
- **UI 라이브러리**: Material Design 3

### Backend & Infrastructure
- **API Proxy**: Cloudflare Workers (Durable Objects 활용)
- **인증**: JWT (HS256)
- **Rate Limiting**: Cloudflare KV Store

### AI & External APIs
- **AI 모델**: Google Gemini API (gemini-2.5-flash-lite)
- **맛집 검색**: 카카오 로컬 API
- **지도 & 길찾기**: 카카오맵 API
- **날씨**: OpenWeatherMap API

### 보안 & 최적화
- **API 키 보호**: Cloudflare Workers를 통한 서버 사이드 API 키 관리
- **토큰 암호화**: flutter_secure_storage를 활용한 안전한 저장
- **캐싱 전략**: 24시간 TTL의 음식 추천 캐싱으로 API 호출 최소화
- **Rate Limiting**: 15분당 100회 요청 제한

## 시작하기

이 프로젝트를 로컬 환경에서 실행하고 개발하기 위한 가이드입니다.

### 1. 환경 설정

- Flutter SDK 설치 ([공식 문서](https://flutter.dev/docs/get-started/install))
- Android Studio 또는 VS Code (Flutter/Dart 플러그인 설치)
- `.env` 파일 설정 (프로젝트 루트에 `.env` 파일을 생성하고 `GEMINI_API_KEY` 및 `APP_ENVIRONMENT` 설정)

### 2. 의존성 설치

프로젝트 루트에서 다음 명령어를 실행하여 필요한 패키지를 설치합니다.

```bash
flutter pub get
```

### 3. iOS Pod 설치 (iOS 개발 시)

iOS 개발 환경에서는 추가적으로 CocoaPods 의존성을 설치해야 합니다.

```bash
cd ios
pod install
```

### 4. 앱 실행

시뮬레이터 또는 실제 기기에서 앱을 실행합니다.

```bash
flutter run
```

## 스토어 링크

앱이 각 스토어에 출시되면 여기에 링크가 추가될 예정입니다.

- **Google Play Store**: [[플레이스토어 링크](https://play.google.com/store/apps/details?id=com.jonghyun.reviewai_flutter&pcampaignid=web_share)]
- **Apple App Store**: [[앱스토어 링크](https://apps.apple.com/kr/app/%EC%9D%B4%EA%B1%B0-%EC%96%B4%EB%95%8C/id6751484486)]


## 라이선스

MIT License

## 문의

궁금한 점이 있으시면 다음 이메일로 문의해주세요: [brian26492@gmail.com]
