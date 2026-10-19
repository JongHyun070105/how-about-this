import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/utils/kakao_api_filter_util.dart';

KakaoPlace _place({
  required String id,
  required String name,
  required String category,
  String? distance,
}) => KakaoPlace(
  id: id,
  placeName: name,
  categoryName: category,
  phone: '',
  addressName: '',
  x: '127.0',
  y: '37.5',
  distance: distance,
);

void main() {
  group('KakaoApiFilterUtil category helpers', () {
    test('카테고리 코드에 알맞은 음식점 유형을 반환한다', () {
      expect(KakaoApiFilterUtil.getCategoryCode(null), 'FD6');
      expect(KakaoApiFilterUtil.getCategoryCode('한식'), 'FD6');
      expect(KakaoApiFilterUtil.getCategoryCode('카페'), 'CE7');
      expect(KakaoApiFilterUtil.getCategoryCode('편의점'), 'CS2');
      expect(KakaoApiFilterUtil.getCategoryCode('알 수 없음'), 'FD6');
    });

    test('편의점은 고정 검색어를 쓰고 다른 카테고리는 음식명을 유지한다', () {
      expect(KakaoApiFilterUtil.getCategorySearchQuery('편의점', '김밥'), '편의점');
      expect(KakaoApiFilterUtil.getCategorySearchQuery('한식', '김밥'), '김밥');
    });
  });

  group('KakaoApiFilterUtil.filterRestaurants', () {
    final places = [
      _place(id: '1', name: '한식집', category: '음식점 > 한식 > 찌개', distance: '500'),
      _place(
        id: '2',
        name: '중식당',
        category: '음식점 > 중식 > 중국음식',
        distance: '1500',
      ),
      _place(id: '3', name: '분식집', category: '음식점 > 분식'),
    ];

    test('최대 거리보다 먼 장소를 제외하고 거리가 없으면 포함한다', () {
      final filtered = KakaoApiFilterUtil.filterRestaurants(
        places,
        maxDistance: 1000,
      );

      expect(filtered.map((place) => place.id), ['1', '3']);
    });

    test('대상 카테고리와 제외 카테고리를 함께 적용한다', () {
      final filtered = KakaoApiFilterUtil.filterRestaurants(
        places,
        targetCategory: '한식',
        excludeCategories: ['찌개'],
      );

      expect(filtered, isEmpty);
    });
  });

  group('KakaoApiFilterUtil.sortRestaurants', () {
    test('거리, 이름, 카테고리 순으로 정렬한다', () {
      final places = [
        _place(id: '3', name: '한강식당', category: '음식점 > 한식', distance: '250'),
        _place(id: '2', name: '가나다식당', category: '음식점 > 중식', distance: '100'),
        _place(id: '1', name: '다라식당', category: '음식점 > 일식'),
      ];

      expect(
        KakaoApiFilterUtil.sortRestaurants(
          places,
        ).map((place) => place.id).toList(),
        ['2', '3', '1'],
      );
      expect(
        KakaoApiFilterUtil.sortRestaurants(
          List<KakaoPlace>.from(places),
          sortType: RestaurantSortType.name,
        ).map((place) => place.placeName).toList(),
        ['가나다식당', '다라식당', '한강식당'],
      );
      expect(
        KakaoApiFilterUtil.sortRestaurants(
          List<KakaoPlace>.from(places),
          sortType: RestaurantSortType.category,
        ).map((place) => place.id).toList(),
        ['1', '2', '3'],
      );
    });
  });
}
