import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/bank_detail.dart';
import 'package:metadata/repositories/bank_chat_repository.dart';
import 'package:metadata/screens/bank_chat_screen.dart';
import 'package:metadata/utils/sa_branch_codes.dart';
import 'package:metadata/widgets/copyable_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _contactId = 'contact-1';

BankDetail _detail({String id = 'a', String number = '1234567890'}) {
  return BankDetail(
    id: id,
    bankName: 'Capitec Bank',
    accountType: 'Savings',
    accountNumber: number,
    branchCode: '470010',
    accountHolder: 'Thabo Mokoena',
    reference: 'INV-204',
  );
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('BankDetail serialisation', () {
    test('round-trips every field', () {
      final decoded = BankDetail.decodeList(
        BankDetail.encodeList([_detail()]),
      );
      expect(decoded, hasLength(1));
      final d = decoded.single;
      expect(d.bankName, 'Capitec Bank');
      expect(d.accountType, 'Savings');
      expect(d.accountNumber, '1234567890');
      expect(d.branchCode, '470010');
      expect(d.accountHolder, 'Thabo Mokoena');
      expect(d.reference, 'INV-204');
    });

    test('keeps a leading zero on the account number', () {
      // The reason every field is a String. Parsed as a number this pays
      // nobody.
      final decoded = BankDetail.decodeList(
        BankDetail.encodeList([_detail(number: '0012345678')]),
      );
      expect(decoded.single.accountNumber, '0012345678');
    });

    test('malformed storage yields an empty list rather than throwing', () {
      expect(BankDetail.decodeList('not json'), isEmpty);
      expect(BankDetail.decodeList('{"not":"a list"}'), isEmpty);
      expect(BankDetail.decodeList(null), isEmpty);
    });

    test('caps a blob that somehow holds more than the maximum', () {
      final tooMany = List.generate(
        9,
        (i) => _detail(id: 'id-$i'),
      );
      expect(
        BankDetail.decodeList(BankDetail.encodeList(tooMany)),
        hasLength(kMaxBankDetails),
      );
    });
  });

  group('BankChatRepository', () {
    test('stores and reads back per contact', () async {
      final container = await _container();
      final repo = container.read(bankChatRepositoryProvider)!;

      expect(await repo.save(_contactId, _detail()), isTrue);
      expect(repo.read(_contactId), hasLength(1));
      // Scoped per contact: another contact's Bank Chat is untouched.
      expect(repo.read('contact-2'), isEmpty);
    });

    test('refuses a fifth entry instead of silently dropping it', () async {
      final container = await _container();
      final repo = container.read(bankChatRepositoryProvider)!;

      for (var i = 0; i < kMaxBankDetails; i++) {
        expect(await repo.save(_contactId, _detail(id: 'id-$i')), isTrue);
      }
      expect(await repo.save(_contactId, _detail(id: 'one-too-many')), isFalse);
      expect(repo.read(_contactId), hasLength(kMaxBankDetails));
    });

    test('saving an existing id edits in place, not appends', () async {
      final container = await _container();
      final repo = container.read(bankChatRepositoryProvider)!;

      await repo.save(_contactId, _detail(id: 'a'));
      await repo.save(
        _contactId,
        _detail(id: 'a').copyWith(accountHolder: 'Renamed'),
      );

      final stored = repo.read(_contactId);
      expect(stored, hasLength(1));
      expect(stored.single.accountHolder, 'Renamed');
    });

    test('delete removes only the named entry', () async {
      final container = await _container();
      final repo = container.read(bankChatRepositoryProvider)!;

      await repo.save(_contactId, _detail(id: 'a'));
      await repo.save(_contactId, _detail(id: 'b'));
      await repo.delete(_contactId, 'a');

      expect(repo.read(_contactId).map((d) => d.id), ['b']);
    });
  });

  group('branch code suggestions', () {
    test('matches on bank name, alias, and code prefix', () {
      expect(
        suggestBranchCodes('capitec').map((e) => e.code),
        contains('470010'),
      );
      // "fnb" is an alias for First National Bank.
      expect(suggestBranchCodes('fnb').map((e) => e.code), contains('250655'));
      expect(
        suggestBranchCodes('4700').map((e) => e.bankName),
        contains('Capitec Bank'),
      );
    });

    test('ranks the already-named bank first on an empty query', () {
      final ranked = suggestBranchCodes('', bankName: 'Nedbank');
      expect(ranked.first.bankName, 'Nedbank');
      expect(ranked.first.code, '198765');
    });

    test('every code in the table is six digits', () {
      for (final entry in kSaBranchCodes) {
        expect(
          entry.code,
          matches(RegExp(r'^\d{6}$')),
          reason: '${entry.bankName} has a malformed branch code',
        );
      }
    });
  });

  group('CopyableField', () {
    testWidgets('copies the raw value, not the grouped display form', (
      tester,
    ) async {
      // A banking app rejects "1234 5678 90", so the spaces must exist only
      // on screen.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CopyableField(
              label: 'Account Number',
              value: '1234567890',
              groupDigits: true,
            ),
          ),
        ),
      );

      expect(find.text('1234 5678 90'), findsOneWidget);
      await tester.tap(find.text('1234 5678 90'));
      await tester.pump();
      expect(copied, '1234567890');
    });

    testWidgets('a field with no value is not copyable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CopyableField(label: 'Reference', value: ''),
          ),
        ),
      );
      expect(find.text('Not set'), findsOneWidget);
      final inkWell = tester.widget<InkWell>(find.byType(InkWell).first);
      expect(inkWell.onTap, isNull);
    });
  });

  group('BankChatButton', () {
    testWidgets('hides itself for a contact with no id', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(
            home: Scaffold(
              body: BankChatButton(contactId: '', contactName: 'Unknown'),
            ),
          ),
        ),
      );
      expect(find.text('Bank Chat'), findsNothing);
    });

    testWidgets('hides itself when there is no local store', (tester) async {
      // No sharedPreferencesProvider override: Bank Chat cannot save, so it
      // must not offer itself rather than opening a screen that silently
      // fails. This is also what keeps every other widget test in the suite
      // from having to boot main()'s wiring.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: BankChatButton(
                contactId: _contactId,
                contactName: 'Thabo',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Bank Chat'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows how many sets are stored', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await container.read(bankChatRepositoryProvider)!.save(
        _contactId,
        _detail(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: BankChatButton(
                contactId: _contactId,
                contactName: 'Thabo',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Bank Chat'), findsOneWidget);
      expect(
        find.text('1 of $kMaxBankDetails saved · tap to copy'),
        findsOneWidget,
      );
    });
  });
}
