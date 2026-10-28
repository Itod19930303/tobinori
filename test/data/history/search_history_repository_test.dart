// SearchHistoryRepositoryImpl のユニットテスト（sqflite_common_ffiのインメモリDB）。
//
// 設計書: docs/design/issue-4-search-history.md 3.4節・DBスキーマ・7章
//
// 【実装エージェントへの前提共有】
// - コンストラクタは
//   `SearchHistoryRepositoryImpl({required Future<Database> Function() openDatabase, DateTime Function()? now})`。
// - テーブル定義は設計書「DBスキーマ」のとおり（本テストの`_createSchema`と同一）。
// - `save`はUNIQUE制約＋`ConflictAlgorithm.replace`で上書きするため、
//   同名再保存で`id`は付け替わってよい。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tobinori/data/history/search_history_repository.dart';

Future<void> _createSchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE search_history (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      station_name TEXT    NOT NULL UNIQUE,
      searched_at  INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_search_history_searched_at '
    'ON search_history (searched_at DESC)',
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late DateTime currentTime;
  late SearchHistoryRepositoryImpl repository;

  Future<Database> openInMemory() async {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );
  }

  setUp(() async {
    db = await openInMemory();
    currentTime = DateTime.fromMillisecondsSinceEpoch(1000);
    repository = SearchHistoryRepositoryImpl(
      openDatabase: () async => db,
      now: () => currentTime,
    );
  });

  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
  });

  Future<void> saveAt(int millis, String name, {int maxCount = 20}) async {
    currentTime = DateTime.fromMillisecondsSinceEpoch(millis);
    await repository.save(name, maxCount: maxCount);
  }

  Future<List<String>> names() async =>
      (await repository.findAll()).map((e) => e.stationName).toList();

  group('findAll', () {
    test('空DBでは空リストを返すこと', () async {
      expect(await repository.findAll(), isEmpty);
    });

    test('保存順と逆（新しい順）で返ること', () async {
      await saveAt(1000, '新宿');
      await saveAt(2000, '渋谷');
      await saveAt(3000, '東京');

      expect(await names(), ['東京', '渋谷', '新宿']);
    });

    test('searchedAtが保存時の時刻（now）になっていること', () async {
      await saveAt(5000, '新宿');

      final entries = await repository.findAll();
      expect(entries.single.searchedAt, DateTime.fromMillisecondsSinceEpoch(5000));
    });

    test('同一ミリ秒で保存してもidの降順で安定した順序になること', () async {
      await saveAt(1000, '新宿');
      await saveAt(1000, '渋谷');
      await saveAt(1000, '東京');

      expect(await names(), ['東京', '渋谷', '新宿']);
    });

    test('最大kSearchHistoryMaxCount（20）件までしか返さないこと', () async {
      for (var i = 0; i < 25; i++) {
        await db.insert('search_history', {
          'station_name': '駅$i',
          'searched_at': i,
        });
      }

      final entries = await repository.findAll();
      expect(entries, hasLength(20));
      expect(entries.first.stationName, '駅24');
    });
  });

  group('save', () {
    test('同名を再保存しても1行のままで、searched_atが更新され先頭に来ること', () async {
      await saveAt(1000, '新宿');
      await saveAt(2000, '渋谷');
      await saveAt(3000, '新宿');

      final entries = await repository.findAll();
      expect(entries.map((e) => e.stationName), ['新宿', '渋谷']);
      expect(entries.first.searchedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });

    test('上限を超えると最古の行が削除されること', () async {
      await saveAt(1000, 'A', maxCount: 3);
      await saveAt(2000, 'B', maxCount: 3);
      await saveAt(3000, 'C', maxCount: 3);
      await saveAt(4000, 'D', maxCount: 3);

      expect(await names(), ['D', 'C', 'B']);
      final rows = await db.query('search_history');
      expect(rows, hasLength(3));
    });

    test('上限ちょうどでは削除されないこと', () async {
      await saveAt(1000, 'A', maxCount: 3);
      await saveAt(2000, 'B', maxCount: 3);
      await saveAt(3000, 'C', maxCount: 3);

      expect(await names(), ['C', 'B', 'A']);
    });

    test('上限削除が失敗したら例外をthrowし、追加しようとした行も残らないこと（ロールバック）', () async {
      await saveAt(1000, 'A', maxCount: 2);
      await saveAt(2000, 'B', maxCount: 2);

      // 上限超過分のDELETEを強制的に失敗させる。
      await db.execute('''
        CREATE TRIGGER fail_delete BEFORE DELETE ON search_history
        BEGIN
          SELECT RAISE(ABORT, 'forced failure');
        END
      ''');

      currentTime = DateTime.fromMillisecondsSinceEpoch(3000);
      await expectLater(
        repository.save('C', maxCount: 2),
        throwsA(anything),
      );

      await db.execute('DROP TRIGGER fail_delete');
      expect(await names(), ['B', 'A']);
    });
  });

  group('delete', () {
    test('指定IDの行のみ削除されること', () async {
      await saveAt(1000, '新宿');
      await saveAt(2000, '渋谷');
      final target = (await repository.findAll())
          .firstWhere((e) => e.stationName == '新宿');

      await repository.delete(target.id);

      expect(await names(), ['渋谷']);
    });

    test('存在しないIDでも例外にならず、他の行に影響しないこと', () async {
      await saveAt(1000, '新宿');

      await repository.delete(9999);

      expect(await names(), ['新宿']);
    });

    test('再保存でidが付け替わった後の古いidのdeleteはno-opであること', () async {
      await saveAt(1000, '新宿');
      final oldId = (await repository.findAll()).single.id;
      await saveAt(2000, '新宿');

      await repository.delete(oldId);

      expect(await names(), ['新宿']);
    });
  });

  group('deleteAll', () {
    test('全件削除されること', () async {
      await saveAt(1000, '新宿');
      await saveAt(2000, '渋谷');

      await repository.deleteAll();

      expect(await repository.findAll(), isEmpty);
    });
  });

  group('DBの遅延オープンと再オープン', () {
    test('DBは初回アクセス時に遅延オープンされ、成功後は使い回されること', () async {
      var calls = 0;
      final repo = SearchHistoryRepositoryImpl(
        openDatabase: () async {
          calls++;
          return db;
        },
        now: () => currentTime,
      );

      expect(calls, 0);
      await repo.findAll();
      await repo.findAll();
      await repo.save('新宿', maxCount: 20);

      expect(calls, 1);
    });

    test('openDatabaseが1回目に失敗しても、2回目の呼び出しで再オープンされ成功すること', () async {
      var calls = 0;
      final repo = SearchHistoryRepositoryImpl(
        openDatabase: () async {
          calls++;
          if (calls == 1) {
            throw Exception('open failed');
          }
          return db;
        },
        now: () => currentTime,
      );

      await expectLater(repo.findAll(), throwsA(anything));
      expect(await repo.findAll(), isEmpty);
      expect(calls, 2);
    });
  });
}
