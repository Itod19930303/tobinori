// RecordSearchHistoryUseCase のユニットテスト。
//
// 設計書: docs/design/issue-4-search-history.md 3.3節・7章
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/data/history/search_history_repository.dart';
import 'package:tobinori/domain/history/record_search_history_usecase.dart';

class MockSearchHistoryRepository extends Mock
    implements SearchHistoryRepository {}

void main() {
  late MockSearchHistoryRepository repository;
  late RecordSearchHistoryUseCase useCase;

  setUp(() {
    repository = MockSearchHistoryRepository();
    useCase = RecordSearchHistoryUseCase(repository);
    when(() => repository.save(any(), maxCount: any(named: 'maxCount')))
        .thenAnswer((_) async {});
  });

  test('kSearchHistoryMaxCountは20であること', () {
    expect(kSearchHistoryMaxCount, 20);
  });

  test('正規化済みの駅名と上限件数でsaveが1回呼ばれること', () async {
    await useCase.call('  新宿駅 ');

    verify(() => repository.save('新宿', maxCount: kSearchHistoryMaxCount))
        .called(1);
  });

  test('「駅」なしの入力もそのまま保存されること', () async {
    await useCase.call('渋谷');

    verify(() => repository.save('渋谷', maxCount: kSearchHistoryMaxCount))
        .called(1);
  });

  test('正規化後に空になる場合はsaveが呼ばれないこと', () async {
    await useCase.call('   ');
    await useCase.call('');

    verifyNever(() => repository.save(any(), maxCount: any(named: 'maxCount')));
  });

  test('Repositoryが例外をthrowしたらそのまま伝播すること', () async {
    when(() => repository.save(any(), maxCount: any(named: 'maxCount')))
        .thenThrow(StateError('db error'));

    expect(() => useCase.call('新宿'), throwsA(isA<StateError>()));
  });
}
