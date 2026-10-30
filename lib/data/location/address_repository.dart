import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart' show Geocoding;
import 'package:tobinori/domain/location/location_point.dart';

/// 逆ジオコーディングで得られた行政区分（住所の構成要素）。
class AddressParts {
  const AddressParts({
    this.administrativeArea,
    this.locality,
    this.subLocality,
    this.street,
  });

  /// 都道府県
  final String? administrativeArea;

  /// 市区町村
  final String? locality;

  /// 町名など
  final String? subLocality;

  /// 住所全体の文字列。端末によっては「日本、〒xxx-xxxx 東京都…１−１ ビル名」の形で入る。
  /// 日本では町名・番地がここにしか入らないことがある。
  final String? street;
}

/// 座標から住所（地名）を取得するRepository。
///
/// 端末（Android標準）の逆ジオコーディングを使う。追加のAPI費用はかからない。
/// 取得できない場合は`null`を返し、呼び出し側が座標表示などに切り替える。
abstract class AddressRepository {
  Future<String?> addressOf(LocationPoint point);
}

/// [AddressRepository]の`geocoding`パッケージを使った実装。
class AddressRepositoryImpl implements AddressRepository {
  /// [lookup]は座標から行政区分の候補を返す関数。省略時は端末の逆ジオコーディングを使う
  /// （テストでは差し替える）。
  AddressRepositoryImpl({
    Future<List<AddressParts>> Function(LocationPoint point)? lookup,
  }) : _lookup = lookup ?? _defaultLookup;

  final Future<List<AddressParts>> Function(LocationPoint point) _lookup;

  static Future<List<AddressParts>> _defaultLookup(LocationPoint point) async {
    final placemarks = await Geocoding().placemarkFromCoordinates(
      point.latitude,
      point.longitude,
      locale: const Locale('ja', 'JP'),
    );
    return [
      for (final p in placemarks)
        AddressParts(
          administrativeArea: p.administrativeArea,
          locality: p.locality,
          subLocality: p.subLocality,
          street: p.street,
        ),
    ];
  }

  @override
  Future<String?> addressOf(LocationPoint point) async {
    try {
      final candidates = await _lookup(point);
      if (candidates.isEmpty) return null;
      final first = candidates.first;
      // 町名・番地まで入っている`street`を優先し、整形できなければ行政区分で組み立てる。
      return formatStreet(first.street) ??
          formatAddress(
            [first.administrativeArea, first.locality, first.subLocality],
          );
    } catch (e) {
      // 座標が例外メッセージに含まれうるため、型名のみを出す。
      debugPrint('住所の取得に失敗しました: ${e.runtimeType}');
      return null;
    }
  }

  /// `street`（住所全体の文字列）を、表示用の「町名・番地まで」の形に整える。
  ///
  /// 先頭の「日本、」と郵便番号、番地の後ろに続くビル名・施設名を取り除き、
  /// 全角の数字とハイフン類を半角に揃える。整形後に何も残らないときは`null`。
  static String? formatStreet(String? street) {
    var value = street?.trim() ?? '';
    value = value.replaceFirst(RegExp(r'^日本[、,]\s*'), '');
    value = value.replaceFirst(RegExp(r'^〒\s*\d{3}-?\d{4}\s*'), '');
    // 番地の後ろに空白区切りで付くビル名・施設名を落とす。
    value = value.split(RegExp(r'[\s　]+')).first;
    value = value
        .replaceAllMapped(
          RegExp('[０-９]'),
          // 全角数字（U+FF10〜）と半角数字（U+0030〜）の差は0xFEE0。
          (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0),
        )
        .replaceAll(RegExp('[−－‐‑‒–]'), '-');
    return value.isEmpty ? null : value;
  }

  /// 住所の構成要素を、空要素と連続する重複を除いて連結する。
  ///
  /// すべて空のときは`null`を返す。
  static String? formatAddress(Iterable<String?> parts) {
    final cleaned = <String>[];
    for (final part in parts) {
      final value = part?.trim() ?? '';
      if (value.isEmpty) continue;
      if (cleaned.isNotEmpty && cleaned.last == value) continue;
      cleaned.add(value);
    }
    return cleaned.isEmpty ? null : cleaned.join();
  }
}
