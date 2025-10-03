// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserLocation _$UserLocationFromJson(Map<String, dynamic> json) => UserLocation(
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$UserLocationToJson(UserLocation instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'accuracy': instance.accuracy,
      'timestamp': instance.timestamp.toIso8601String(),
    };

KakaoPlace _$KakaoPlaceFromJson(Map<String, dynamic> json) => KakaoPlace(
  id: json['id'] as String,
  placeName: json['place_name'] as String,
  categoryName: json['category_name'] as String,
  categoryGroupCode: json['category_group_code'] as String?,
  categoryGroupName: json['category_group_name'] as String?,
  phone: json['phone'] as String,
  addressName: json['address_name'] as String,
  roadAddressName: json['road_address_name'] as String?,
  x: json['x'] as String,
  y: json['y'] as String,
  placeUrl: json['place_url'] as String?,
  distance: json['distance'] as String?,
);

Map<String, dynamic> _$KakaoPlaceToJson(KakaoPlace instance) =>
    <String, dynamic>{
      'id': instance.id,
      'place_name': instance.placeName,
      'category_name': instance.categoryName,
      'category_group_code': instance.categoryGroupCode,
      'category_group_name': instance.categoryGroupName,
      'phone': instance.phone,
      'address_name': instance.addressName,
      'road_address_name': instance.roadAddressName,
      'x': instance.x,
      'y': instance.y,
      'place_url': instance.placeUrl,
      'distance': instance.distance,
    };

KakaoMeta _$KakaoMetaFromJson(Map<String, dynamic> json) => KakaoMeta(
  totalCount: (json['total_count'] as num).toInt(),
  pageableCount: (json['pageable_count'] as num).toInt(),
  isEnd: json['is_end'] as bool,
);

Map<String, dynamic> _$KakaoMetaToJson(KakaoMeta instance) => <String, dynamic>{
  'total_count': instance.totalCount,
  'pageable_count': instance.pageableCount,
  'is_end': instance.isEnd,
};

KakaoSearchResponse _$KakaoSearchResponseFromJson(Map<String, dynamic> json) =>
    KakaoSearchResponse(
      meta: KakaoMeta.fromJson(json['meta'] as Map<String, dynamic>),
      documents: (json['documents'] as List<dynamic>)
          .map((e) => KakaoPlace.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$KakaoSearchResponseToJson(
  KakaoSearchResponse instance,
) => <String, dynamic>{'meta': instance.meta, 'documents': instance.documents};
