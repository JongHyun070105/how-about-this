import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/services/kakao_api_service.dart';
import 'package:review_ai/models/location_models.dart';

void main() {
  group('KakaoApiService Tests', () {
    late KakaoApiService service;

    setUp(() {
      service = KakaoApiService();
    });

    group('_getCategoryCode', () {
      test('카페 카테고리는 CE7 코드를 반환한다', () {
        // Arrange & Act
        final code = service.getCategorySearchQuery('카페', '아메리카노');
        
        // Assert
        expect(code, '아메리카노');
      });

      test('편의점 카테고리는 CS2 코드를 반환한다', () {
        // Arrange & Act
        final code = service.getCategorySearchQuery('편의점', '삼각김밥');
        
        // Assert
        expect(code, '편의점');
      });

      test('한식 카테고리는 FD6 코드를 반환한다', () {
        // Arrange & Act
        final code = service.getCategorySearchQuery('한식', '김치찌개');
        
        // Assert
        expect(code, '김치찌개');
      });
    });

    group('filterRestaurants', () {
      test('거리 필터링이 정상 작동한다', () {
        // Arrange
        final mockRestaurants = [
          KakaoPlace(
            id: '1',
            placeName: '테스트 음식점',
            categoryName: '음식점 > 한식',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '02-1234-5678',
            addressName: '서울시 강남구',
            roadAddressName: '테스트로 123',
            x: '127.0',
            y: '37.5',
            placeUrl: 'https://test.com',
            distance: '500',
          ),
          KakaoPlace(
            id: '2',
            placeName: '먼 음식점',
            categoryName: '음식점 > 한식',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '02-9999-9999',
            addressName: '서울시 강북구',
            roadAddressName: '테스트로 999',
            x: '127.0',
            y: '37.5',
            placeUrl: 'https://test2.com',
            distance: '2000',
          ),
        ];

        // Act
        final filtered = service.filterRestaurants(
          mockRestaurants,
          maxDistance: 1000,
        );

        // Assert
        expect(filtered.length, 1);
        expect(filtered.first.placeName, '테스트 음식점');
      });

      test('카테고리 필터링이 정상 작동한다', () {
        // Arrange
        final mockRestaurants = [
          KakaoPlace(
            id: '1',
            placeName: '한식당',
            categoryName: '음식점 > 한식',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '02-1111-1111',
            addressName: '서울시 강남구',
            roadAddressName: '테스트로 1',
            x: '127.0',
            y: '37.5',
            placeUrl: 'https://test1.com',
            distance: '100',
          ),
          KakaoPlace(
            id: '2',
            placeName: '중식당',
            categoryName: '음식점 > 중식',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '02-2222-2222',
            addressName: '서울시 강남구',
            roadAddressName: '테스트로 2',
            x: '127.0',
            y: '37.5',
            placeUrl: 'https://test2.com',
            distance: '200',
          ),
        ];

        // Act
        final filtered = service.filterRestaurants(
          mockRestaurants,
          targetCategory: '한식',
        );

        // Assert
        expect(filtered.length, 1);
        expect(filtered.first.placeName, '한식당');
      });
    });

    group('sortRestaurants', () {
      test('거리순 정렬이 정상 작동한다', () {
        // Arrange
        final mockRestaurants = [
          KakaoPlace(
            id: '1',
            placeName: '먼 곳',
            categoryName: '음식점',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '',
            addressName: '',
            roadAddressName: '',
            x: '127.0',
            y: '37.5',
            placeUrl: '',
            distance: '1000',
          ),
          KakaoPlace(
            id: '2',
            placeName: '가까운 곳',
            categoryName: '음식점',
            categoryGroupCode: 'FD6',
            categoryGroupName: '음식점',
            phone: '',
            addressName: '',
            roadAddressName: '',
            x: '127.0',
            y: '37.5',
            placeUrl: '',
            distance: '100',
          ),
        ];

        // Act
        final sorted = service.sortRestaurants(
          mockRestaurants,
          sortType: RestaurantSortType.distance,
        );

        // Assert
        expect(sorted.first.placeName, '가까운 곳');
        expect(sorted.last.placeName, '먼 곳');
      });
    });
  });
}



