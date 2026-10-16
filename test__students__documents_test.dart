import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiksha_desk/modules/students/documents/document_files.dart';
import 'package:shiksha_desk/modules/students/documents/document_models.dart';
import 'package:shiksha_desk/modules/students/documents/document_repository.dart';
import 'package:shiksha_desk/modules/students/documents/documents_pdf.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/reporting/pdf_report_renderer.dart';

import '../test_support.dart';

void main() {
  group('document types', () {
    test('required: for everyone, for some classes, or only reserved categories', () {
      const all = DocumentType(key: 'a', label: 'A', isRequired: true);
      const some = DocumentType(key: 'b', label: 'B', isRequired: true, programIds: ['11sci']);
      const caste = DocumentType(key: 'c', label: 'C', isRequired: true, onlyReserved: true);
      const optional = DocumentType(key: 'd', label: 'D');
      expect(all.requiredFor(), isTrue);
      expect(some.requiredFor(programId: '11sci'), isTrue);
      expect(some.requiredFor(programId: '12sci'), isFalse);
      expect(caste.requiredFor(category: 'OBC'), isTrue);
      expect(caste.requiredFor(category: 'Open'), isFalse);
      expect(caste.requiredFor(category: null), isFalse);
      expect(optional.requiredFor(), isFalse);
    });

    test('saved list is read back; unreadable gives the standard list; keys are unique', () {
      final mine = [...DocumentTypes.defaults.take(2), const DocumentType(key: 'bonafide', label: 'Bonafide', isRequired: true)];
      final back = DocumentTypes.decode(DocumentTypes.encode(mine));
      expect(back.map((t) => (t.key, t.label, t.isRequired)), mine.map((t) => (t.key, t.label, t.isRequired)));
      expect(DocumentTypes.decode('nonsense'), DocumentTypes.defaults);
      expect(DocumentTypes.keyFor('Bonafide copy!', const []), 'bonafide_copy');
      expect(DocumentTypes.keyFor('Bonafide', const ['bonafide']), 'bonafide_2');
      // The Aadhaar card copy is protected by default.
      expect(DocumentTypes.defaults.firstWhere((t) => t.key == 'aadhaar_card').sensitive, isTrue);
    });

    test('checklist: pending required documents; "not needed" is not missing', () {
      final lines = documentChecklist(
        DocumentTypes.defaults,
        const [
          StudentDocument(studentId: 's', typeKey: 'ssc_marksheet'),
          StudentDocument(studentId: 's', typeKey: 'leaving_certificate', status: DocumentStatus.pending),
          StudentDocument(studentId: 's', typeKey: 'aadhaar_card', status: DocumentStatus.notNeeded),
          StudentDocument(studentId: 's', typeKey: 'old_type'), // type removed later: still listed
        ],
        category: 'Open',
      );
      final missing = lines.where(isMissing).map((l) => l.type.key).toList();
      expect(missing, ['leaving_certificate', 'photos']); // caste certificate not needed for Open
      expect(lines.last.type.key, 'old_type');
    });
  });

  test('records: one per student and type, updated in place, pages in order, removable', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    final repo = DocumentRepository(db, testSession, AppSettingsRepository(db, testSession));
    final id = await repo.save(const StudentDocument(studentId: 's1', typeKey: 'ssc_marksheet', files: ['documents/s1/a.jpg']));
    final again = await repo.save(StudentDocument(
      studentId: 's1',
      typeKey: 'ssc_marksheet',
      number: ' 123456 ',
      issuedOn: DateTime(2025, 5, 13),
      isOriginal: true,
      verified: true,
      files: const ['documents/s1/b.jpg', 'documents/s1/a.jpg'],
    ));
    expect(again, id);
    final docs = await repo.forStudent('s1');
    expect(docs, hasLength(1));
    expect(docs.single.number, '123456');
    expect(docs.single.files, ['documents/s1/b.jpg', 'documents/s1/a.jpg']);
    expect(docs.single.isOriginal && docs.single.verified, isTrue);
    expect((await repo.forStudents(['s1', 's2']))['s1'], hasLength(1));

    await repo.remove(id);
    expect(await repo.forStudent('s1'), isEmpty);

    // Types: the standard list until changed.
    expect(await repo.types(), DocumentTypes.defaults);
    await repo.saveTypes([const DocumentType(key: 'x', label: 'X')]);
    expect((await repo.types()).single.label, 'X');
  });

  test('pending documents: only students missing required ones, in the institution order', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    final repo = DocumentRepository(db, testSession, AppSettingsRepository(db, testSession));
    // s1 gave everything required (Aadhaar marked "not needed").
    for (final key in ['ssc_marksheet', 'leaving_certificate', 'photos']) {
      await repo.save(StudentDocument(studentId: 's1', typeKey: key));
    }
    await repo.save(const StudentDocument(studentId: 's1', typeKey: 'aadhaar_card', status: DocumentStatus.notNeeded));
    // s2 gave only the marksheet; the TC is recorded as pending.
    await repo.save(const StudentDocument(studentId: 's2', typeKey: 'ssc_marksheet'));
    await repo.save(const StudentDocument(studentId: 's2', typeKey: 'leaving_certificate', status: DocumentStatus.pending));

    final pending = await repo.pendingFor(const [
      (studentId: 's1', programId: 'p1'),
      (studentId: 's2', programId: 'p1'),
      (studentId: 's3', programId: null),
    ]);
    expect(pending.containsKey('s1'), isFalse);
    expect(pending['s2']!.map((t) => t.key), ['leaving_certificate', 'aadhaar_card', 'photos']);
    // Nothing recorded at all; no category, so no caste certificate.
    expect(pending['s3']!.map((t) => t.key), ['ssc_marksheet', 'leaving_certificate', 'aadhaar_card', 'photos']);
    expect(await repo.pendingFor(const []), isEmpty);
  });

  group('files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('docs'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('photos are made smaller and kept under the student; PDFs kept as they are', () async {
      final files = DocumentFiles(dir);
      final big = Uint8List.fromList(img.encodePng(img.Image(width: 3000, height: 4000)));
      final path = await files.addImage('s1', big);
      expect(path, startsWith('documents/s1/'));
      expect(path, endsWith('.jpg'));
      final saved = img.decodeJpg((await files.read(path))!)!;
      expect([saved.width, saved.height], [1275, 1700]);

      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 tiny'));
      final pdfPath = await files.addPdf('s1', pdf);
      expect(await files.read(pdfPath), pdf);
      expect(DocumentFiles.isPdf(pdfPath), isTrue);

      expect(() => files.addPdf('s1', Uint8List.fromList(utf8.encode('not a pdf'))), throwsA(isA<DocumentUnreadable>()));
      expect(() => files.addPdf('s1', Uint8List(DocumentFiles.maxPdfBytes + 1)), throwsA(isA<DocumentTooLarge>()));
      expect(() => files.addImage('s1', Uint8List.fromList([1, 2, 3])), throwsA(isA<DocumentUnreadable>()));
    });
  });

  test('all documents in one PDF: a contents page, then every page', () async {
    final fonts = ReportFonts(
      ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()),
      ByteData.sublistView(File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync()),
    );
    final page = Uint8List.fromList(img.encodeJpg(img.Image(width: 120, height: 160)));
    final bytes = await buildDocumentsPdf(
      title: 'Documents of Fatima Shaikh',
      about: const ['Fatima Shaikh', 'STU-000001'],
      parts: [
        (label: '10th (SSC) Marksheet', details: 'Original', pages: [page, page]),
        (label: 'Aadhaar Card copy', details: 'Copy', pages: [page]),
      ],
      fonts: fonts,
      generatedLine: 'test',
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    final text = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 4); // contents + 3 pages
  });
}
