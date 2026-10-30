// 現在地の住所取得（逆ジオコーディング）のテスト。
//
// 住所の整形は純粋関数 `AddressRepositoryImpl.formatAddress` に切り出し、
// 端末の逆ジオコーディング呼び出しは関数注入で差し替えて検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/data/location/address_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';

void main() {
  const point = LocationPoint(latitude: 35.6896, longitude: 139.7006);

  group('formatAddress', () {
    test('都道府県・市区町村・町名を順につなぐこと', () {
      expect(
        AddressRepositoryImpl.formatAddress(['東京都', '新宿区', '西新宿']),
        '東京都新宿区西新宿',
      );
    });

    test('null・空文字・空白だけの要素は取り除くこと', () {
      expect(
        AddressRepositoryImpl.formatAddress(['東京都', null, '', '  ', '新宿区']),
        '東京都新宿区',
      );
    });

    test('同じ値が連続する場合は重ねないこと（例: 市と区が同名）', () {
      expect(
        AddressRepositoryImpl.formatAddress(['東京都', '東京都', '新宿区']),
        '東京都新宿区',
      );
    });

    test('すべて空のときはnullを返すこと', () {
      expect(AddressRepositoryImpl.formatAddress([null, '', ' ']), isNull);
      expect(AddressRepositoryImpl.formatAddress([]), isNull);
    });
  });

  group('formatStreet', () {
    test('先頭の「日本、」と郵便番号を取り除くこと', () {
      expect(
        AddressRepositoryImpl.formatStreet('日本、〒100-0001 東京都千代田区千代田１−１'),
        '東京都千代田区千代田1-1',
      );
    });

    test('番地の後ろに続くビル名・施設名を取り除くこと', () {
      expect(
        AddressRepositoryImpl.formatStreet(
          '日本、〒100-0001 東京都千代田区千代田１−１ サンプルビル',
        ),
        '東京都千代田区千代田1-1',
      );
    });

    test('全角の数字とハイフン類を半角に揃えること', () {
      expect(
        AddressRepositoryImpl.formatStreet('東京都千代田区千代田１２−３４−５'),
        '東京都千代田区千代田12-34-5',
      );
      expect(
        AddressRepositoryImpl.formatStreet('東京都千代田区千代田１－２'),
        '東京都千代田区千代田1-2',
      );
    });

    test('「日本、」や郵便番号が無くても整形できること', () {
      expect(
        AddressRepositoryImpl.formatStreet('千代田１−１'),
        '千代田1-1',
      );
    });

    test('空文字・空白のみ・nullのときはnullを返すこと', () {
      expect(AddressRepositoryImpl.formatStreet(null), isNull);
      expect(AddressRepositoryImpl.formatStreet(''), isNull);
      expect(AddressRepositoryImpl.formatStreet('  '), isNull);
      expect(AddressRepositoryImpl.formatStreet('日本、〒100-0001'), isNull);
    });
  });

  group('addressOf', () {
    test('streetがあれば町名・番地まで含む住所を返すこと', () async {
      final repository = AddressRepositoryImpl(
        lookup: (point) async => [
          const AddressParts(
            administrativeArea: '東京都',
            locality: '千代田区',
            street: '日本、〒100-0001 東京都千代田区千代田１−１ サンプルビル',
          ),
        ],
      );

      expect(await repository.addressOf(point), '東京都千代田区千代田1-1');
    });

    test('streetが整形できないときは行政区分にフォールバックすること', () async {
      final repository = AddressRepositoryImpl(
        lookup: (point) async => [
          const AddressParts(
            administrativeArea: '東京都',
            locality: '千代田区',
            street: '日本、〒100-0001',
          ),
        ],
      );

      expect(await repository.addressOf(point), '東京都千代田区');
    });

    test('取得した行政区分から住所文字列を返すこと', () async {
      final repository = AddressRepositoryImpl(
        lookup: (point) async => [
          const AddressParts(
            administrativeArea: '東京都',
            locality: '新宿区',
            subLocality: '西新宿',
          ),
        ],
      );

      expect(await repository.addressOf(point), '東京都新宿区西新宿');
    });

    test('lookupに現在地の座標がそのまま渡ること', () async {
      LocationPoint? received;
      final repository = AddressRepositoryImpl(
        lookup: (p) async {
          received = p;
          return [];
        },
      );

      await repository.addressOf(point);

      expect(received, point);
    });

    test('候補が0件のときはnullを返すこと', () async {
      final repository = AddressRepositoryImpl(lookup: (_) async => []);

      expect(await repository.addressOf(point), isNull);
    });

    test('lookupが例外を投げてもnullを返し、例外を外に出さないこと', () async {
      final repository = AddressRepositoryImpl(
        lookup: (_) async => throw Exception('network'),
      );

      expect(await repository.addressOf(point), isNull);
    });
  });
}
