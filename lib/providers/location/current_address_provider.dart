import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/data/location/address_repository.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';

/// `AddressRepository`のDIポイント。
final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepositoryImpl();
});

/// 現在地の住所（地名）。
///
/// 現在地が取得できるたびに取り直す。現在地が未取得のとき、および住所を
/// 取得できなかったときは`null`（呼び出し側が座標表示に切り替える）。
final currentAddressProvider = FutureProvider<String?>((ref) async {
  final point = ref.watch(currentLocationPointProvider);
  if (point == null) return null;
  return ref.watch(addressRepositoryProvider).addressOf(point);
});
