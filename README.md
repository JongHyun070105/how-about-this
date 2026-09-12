# 이거어때?

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/JongHyun070105/how-about-this/aquarium-output/aquarium-github-dark.svg?v=1.3.0">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/JongHyun070105/how-about-this/aquarium-output/aquarium-coral-day.svg?v=1.3.0">
  <img alt="테마별 모습으로 자유롭게 움직이는 기여자, 릴리스 전설 생물, 저장소 활동 현상을 보여주는 how-about-this Repo Aquarium 세계" src="https://raw.githubusercontent.com/JongHyun070105/how-about-this/aquarium-output/aquarium-coral-day.svg?v=1.3.0" width="900">
</picture>

## 개요

이거어때?는 이미지, 음식명, 별점을 입력받아 Gemini AI(gemini-3.5-flash-lite)를 통해 음식 리뷰를 3개 생성하고, 사용자가 선택하여 복사할 수 있는 Flutter 애플리케이션입니다. 이 앱은 사용자에게 편리하고 다양한 리뷰 옵션을 제공하여 음식 리뷰 작성 과정을 간소화합니다.

## 주요 기능

### 🤖 AI 기반 리뷰 작성
- **이미지 업로드**: 음식 사진을 업로드할 수 있습니다.
- **음식 정보 입력**: 음식명과 별점을 입력하여 리뷰 생성의 기반을 마련합니다.
- **작성 스타일 선택**: 음식 리뷰를 작성할 스타일을 선택할 수 있습니다.
- **Gemini AI 연동**: Gemini AI를 활용하여 입력된 정보를 바탕으로 3가지의 음식 리뷰를 생성합니다.
- **리뷰 선택 및 복사**: 생성된 리뷰 중 마음에 드는 것을 선택하여 간편하게 복사할 수 있습니다.
- **리뷰 기록**: 생성된 리뷰들을 기록하여 다시 볼 수 있습니다.

### 🍽️ 오늘의 음식 추천
- **카테고리별 추천**: 한식, 중식, 일식, 양식, 분식 등 다양한 카테고리별 음식 추천
- **개인화 추천 시스템**: 사용자의 식사 기록과 선호도를 분석하여 맞춤 추천 제공
- **날씨 기반 추천**: 실시간 날씨 정보를 활용한 스마트 추천 (비 오는 날 따뜻한 국물 요리, 맑은 날 냉면 등)
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
- **AI 모델**: Google Gemini API (gemini-3.5-flash-lite)
- **맛집 검색**: 카카오맵 API
- **지도 & 길찾기**: 카카오맵 API
- **날씨**: OpenWeatherMap API

### 보안 & 인프라
- **CI/CD**: GitHub Actions를 통한 자동화된 빌드 및 배포 프로세스
- **API 보호**: Cloudflare Workers를 통한 고도화된 프록시 및 Rate Limiting
- **모니터링**: Firebase Crashlytics를 통한 실시간 에러 트래킹 및 성능 모니터링
- **캐싱 전략**: 24시간 TTL 기반의 지능적 추천 데이터 캐싱
- **보안**: flutter_secure_storage를 이용한 민감 정보 암호화 저장

## 아키텍처 및 품질
- **Clean Architecture**: Domain, Data, Presentation 레이어 분리로 유지보수성 극대화
- **OOP 원칙**: SOLID 원칙을 준수하는 객체 지향 설계
- **로깅 시스템**: 프로덕션 레벨의 체계적인 로깅 인프라 구축

## 시작하기

이 프로젝트를 로컬 환경에서 실행하고 개발하기 위한 가이드입니다.

### 1. 환경 설정

- Flutter SDK 설치 ([공식 문서](https://flutter.dev/docs/get-started/install))
- Android Studio 또는 VS Code (Flutter/Dart 플러그인 설치)
- `.env` 파일 설정 (프로젝트 루트에 `.env` 파일을 생성하고 `GEMINI_API_KEY` 및 `KAKAO_API_KEY`, `OPEN_WEATHER_MAP_API_KEY`, `APP_ENVIRONMENT` 설정)

### 2. 의존성 설치

프로젝트 루트에서 다음 명령어를 실행하여 필요한 패키지를 설치합니다.

```bash
flutter pub get
```

### 3. iOS Pod 설치

iOS 개발 환경에서는 추가적으로 CocoaPods 의존성을 설치해야 합니다.

```bash
cd ios
pod install
```

## CI/CD 및 배포 전략

이 프로젝트는 브랜치별 이원화 배포 시스템 및 고도화된 자동화 파이프라인을 갖추고 있습니다.

### 파이프라인 및 자동화 도구
- **GitHub Actions**: 자동화된 빌드, 테스트 및 배포 프로세스
- **ReviewDog**: Pull Request 생성 시 `flutter analyze` 결과를 바탕으로 자동 코드 린트 리뷰 작성
- **Codecov**: 테스트 커버리지 측정 및 PR 브리핑 리포트 제공 (설정 파일을 통해 UI 및 자동 생성 코드 배제)
- **Release Please**: `main` 병합 시 커밋 메시지(Conventional Commits)를 분석하여 자동 버전 펌핑 및 `CHANGELOG.md` 발행
- **Branch Protection**: `main` 브랜치에 대한 강제 푸시 차단 및 필수 PR 리뷰 사이클 적용으로 코드 무결성 보장

### 배포 워크플로우
- **`develop` 브랜치**: 푸시 시 **Firebase App Distribution**을 통해 테스터에게 APK가 자동 배포됩니다.
- **`main` 브랜치**: 푸시 시 **Google Play Store** 내부 테스트 트랙으로 AAB가 자동 빌드 및 업로드됩니다.
- **Cloudflare**: `cloudflare-worker` 폴더 변경 시 Wrangler를 통해 Worker 스크립트가 자동 배포됩니다.

## 앱 실행 방법

## 스토어 링크

- **Google Play Store**: [[플레이스토어 링크](https://play.google.com/store/apps/details?id=com.jonghyun.reviewai_flutter&pcampaignid=web_share)]
- **Apple App Store**: 업데이트 진행 X

## 라이선스

MIT License
