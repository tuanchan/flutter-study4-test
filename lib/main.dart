import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HighlightManager.load();
  await TestHistoryManager.load();
  runApp(const Study4CloneApp());
}

class Study4CloneApp extends StatelessWidget {
  const Study4CloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STUDY4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.page,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue),
        fontFamily: 'Arial',
      ),
      home: const TestLibraryPage(),
    );
  }
}

class AppColors {
  static const blue = Color(0xFF2F55B7);
  static const paleBlue = Color(0xFFEAF3FF);
  static const page = Color(0xFFF5F6F8);
  static const border = Color(0xFFDADDE3);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const chip = Color(0xFFF1F1F1);
  static const greenPanel = Color(0xFFDDF5E7);
  static const greenText = Color(0xFF00765D);
}

const String defaultTestRoot = 'assets/data/TOEIC/Sample/Sample TOEIC Test 1';

class PartMeta {
  final int number;
  final String folder;
  final String label;
  final int count;

  const PartMeta(this.number, this.folder, this.label, this.count);
}

class ToeicQuestion {
  final String qid;
  final int number;
  final String text;
  final Map<String, String> options;
  final String answer;
  final String transcript;
  final List<String> audioFiles;
  final List<String> imageFiles;
  final String contextText;

  ToeicQuestion({
    required this.qid,
    required this.number,
    required this.text,
    required this.options,
    required this.answer,
    required this.transcript,
    required this.audioFiles,
    required this.imageFiles,
    this.contextText = '',
  });

  factory ToeicQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as Map?) ?? {};
    return ToeicQuestion(
      qid: (json['qid'] ?? json['question_number'] ?? '').toString(),
      number: (json['question_number'] as num).toInt(),
      text: (json['question_text'] ?? '').toString(),
      options: rawOptions.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      answer: (json['correct_answer'] ?? '').toString(),
      transcript: (json['transcript'] ?? '').toString(),
      audioFiles: ((json['audio_files'] as List?) ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      imageFiles: ((json['image_files'] as List?) ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      contextText: (json['context_text'] ?? '').toString(),
    );
  }

  ToeicQuestion copyWith({String? contextText}) {
    return ToeicQuestion(
      qid: qid,
      number: number,
      text: text,
      options: options,
      answer: answer,
      transcript: transcript,
      audioFiles: audioFiles,
      imageFiles: imageFiles,
      contextText: contextText ?? this.contextText,
    );
  }
}

class PartData {
  final PartMeta meta;
  final List<ToeicQuestion> questions;

  PartData(this.meta, this.questions);
}

class TextHighlightMark {
  final int start;
  final int end;
  final Color? color;
  final bool strikeThrough;
  final String? note;

  const TextHighlightMark({
    required this.start,
    required this.end,
    this.color,
    this.strikeThrough = false,
    this.note,
  });

  bool overlaps(int otherStart, int otherEnd) {
    return start < otherEnd && otherStart < end;
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
      'color': color?.value,
      'strikeThrough': strikeThrough,
      'note': note,
    };
  }

  factory TextHighlightMark.fromJson(Map<String, dynamic> json) {
    return TextHighlightMark(
      start: json['start'] as int,
      end: json['end'] as int,
      color: json['color'] != null ? Color(json['color'] as int) : null,
      strikeThrough: json['strikeThrough'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }
}

class TestData {
  final String root;
  final String name;
  final List<PartData> parts;

  TestData({required this.root, required this.name, required this.parts});

  int get totalQuestions =>
      parts.fold(0, (sum, part) => sum + part.questions.length);
}

class TestRepository {
  static Future<String> _readString(String path) async {
    if (path.startsWith('assets/')) {
      return await rootBundle.loadString(path);
    } else {
      return await File(path).readAsString();
    }
  }

  static Future<TestData> load({String root = defaultTestRoot}) async {
    final isAsset = root.startsWith('assets/');
    final AssetManifest? manifest = isAsset
        ? await AssetManifest.loadFromAssetBundle(rootBundle)
        : null;
    final infoRaw = await _readString('$root/test_info.json');
    final info = jsonDecode(infoRaw) as Map<String, dynamic>;
    final parts = <PartData>[];
    final questionPaths = _questionJsonPaths(root, manifest);

    for (final questionPath in questionPaths) {
      final folder = _folderFromQuestionPath(questionPath);
      final raw = await _readString(questionPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      var questions = ((decoded['questions'] as List?) ?? [])
          .map((item) => ToeicQuestion.fromJson(item as Map<String, dynamic>))
          .toList();
      final partNumber = _partNumberFromFolder(folder);
      if (partNumber == 6 || partNumber == 7) {
        final rawHtmlPath = '$root/$folder/raw.html';
        bool hasHtml = false;
        String htmlContent = '';
        if (isAsset) {
          hasHtml = manifest!.listAssets().contains(rawHtmlPath);
          if (hasHtml) {
            htmlContent = await rootBundle.loadString(rawHtmlPath);
          }
        } else {
          final file = File(rawHtmlPath);
          hasHtml = await file.exists();
          if (hasHtml) {
            htmlContent = await file.readAsString();
          }
        }
        if (hasHtml) {
          final contextByQid = _contextByQidFromRawHtml(htmlContent);
          if (contextByQid.isNotEmpty) {
            questions = [
              for (final question in questions)
                question.copyWith(
                  contextText:
                      contextByQid[question.qid] ?? question.contextText,
                ),
            ];
          }
        }
      }
      final meta = PartMeta(
        partNumber,
        folder,
        'Part $partNumber',
        questions.length,
      );
      parts.add(PartData(meta, questions));
    }

    final testName =
        info['test_name'] ?? root.split(Platform.isWindows ? '\\' : '/').last;
    return TestData(root: root, name: testName.toString(), parts: parts);
  }

  static Future<List<TestSummary>> loadSummaries() async {
    final summaries = <TestSummary>[];

    // 1. Load from assets
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetRoots =
          manifest
              .listAssets()
              .where(
                (path) =>
                    path.startsWith('assets/data/') &&
                    path.endsWith('/questions.json'),
              )
              .map((path) {
                final withoutFile = path.substring(0, path.lastIndexOf('/'));
                return withoutFile.substring(0, withoutFile.lastIndexOf('/'));
              })
              .toSet()
              .toList()
            ..sort();

      for (final root in assetRoots) {
        final info = await _loadTestInfo(root);
        if (info == null) {
          continue;
        }
        final questionPaths = _questionJsonPaths(root, manifest);
        var totalQuestions = 0;
        for (final questionPath in questionPaths) {
          final raw = await _readString(questionPath);
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          totalQuestions += ((decoded['questions'] as List?) ?? []).length;
        }
        summaries.add(
          TestSummary(
            root: root,
            title: (info['test_name'] ?? root.split('/').last).toString(),
            exam: _examFromRoot(root),
            year: _yearFromRoot(root),
            parts: questionPaths.length,
            questions: totalQuestions,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading asset summaries: $e');
    }

    // 2. Load from local documents directory
    try {
      final dir = await getApplicationDocumentsDirectory();
      final toeicDir = Directory('${dir.path}/TOEIC');
      if (await toeicDir.exists()) {
        final years = toeicDir.listSync();
        for (final yearEntity in years) {
          if (yearEntity is Directory) {
            final tests = yearEntity.listSync();
            for (final testEntity in tests) {
              if (testEntity is Directory) {
                final infoFile = File('${testEntity.path}/test_info.json');
                if (await infoFile.exists()) {
                  final infoRaw = await infoFile.readAsString();
                  final info = jsonDecode(infoRaw) as Map<String, dynamic>;
                  final questionPaths = _questionJsonPaths(
                    testEntity.path,
                    null,
                  );
                  var totalQuestions = 0;
                  for (final qPath in questionPaths) {
                    final raw = await File(qPath).readAsString();
                    final decoded = jsonDecode(raw) as Map<String, dynamic>;
                    totalQuestions +=
                        ((decoded['questions'] as List?) ?? []).length;
                  }
                  summaries.add(
                    TestSummary(
                      root: testEntity.path,
                      title:
                          (info['test_name'] ??
                                  testEntity.path
                                      .split(Platform.isWindows ? '\\' : '/')
                                      .last)
                              .toString(),
                      exam: 'TOEIC',
                      year: yearEntity.path
                          .split(Platform.isWindows ? '\\' : '/')
                          .last,
                      parts: questionPaths.length,
                      questions: totalQuestions,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading local summaries: $e');
    }

    summaries.sort((a, b) {
      final category = '${a.exam}/${a.year}'.compareTo('${b.exam}/${b.year}');
      if (category != 0) {
        return category;
      }
      return _naturalCompare(a.title, b.title);
    });
    return summaries;
  }

  static Future<Map<String, dynamic>?> _loadTestInfo(String root) async {
    try {
      final infoRaw = await _readString('$root/test_info.json');
      return jsonDecode(infoRaw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static List<String> _questionJsonPaths(String root, AssetManifest? manifest) {
    if (manifest == null) {
      // Local path
      final dir = Directory(root);
      if (!dir.existsSync()) return [];
      final paths = <String>[];
      final parts = dir.listSync();
      for (final p in parts) {
        if (p is Directory) {
          final qJson = File('${p.path}/questions.json');
          if (qJson.existsSync()) {
            paths.add(qJson.path);
          }
        }
      }
      paths.sort((a, b) {
        final aPart = _partNumberFromFolder(_folderFromQuestionPath(a));
        final bPart = _partNumberFromFolder(_folderFromQuestionPath(b));
        return aPart.compareTo(bPart);
      });
      return paths;
    } else {
      // Asset path
      final prefix = '$root/';
      final paths = manifest
          .listAssets()
          .where(
            (path) =>
                path.startsWith(prefix) && path.endsWith('/questions.json'),
          )
          .toList();
      paths.sort((a, b) {
        final aPart = _partNumberFromFolder(_folderFromQuestionPath(a));
        final bPart = _partNumberFromFolder(_folderFromQuestionPath(b));
        return aPart.compareTo(bPart);
      });
      return paths;
    }
  }

  static String _folderFromQuestionPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final withoutFile = normalized.substring(0, normalized.lastIndexOf('/'));
    return withoutFile.substring(withoutFile.lastIndexOf('/') + 1);
  }

  static int _partNumberFromFolder(String folder) {
    final match = RegExp(r'^Part(\d+)').firstMatch(folder);
    return int.tryParse(match?.group(1) ?? '') ?? 999;
  }

  static Map<String, String> _contextByQidFromRawHtml(String rawHtml) {
    final result = <String, String>{};
    final groupPattern = RegExp(
      r"<div class='question-group-wrapper'>([\s\S]*?)(?=<div class='question-group-wrapper'>|<div class='practice-submit-panel|</form>)",
      caseSensitive: false,
    );
    final contextPattern = RegExp(
      r"<div class='context-content[^']*'>([\s\S]*?)</div>\s*</div>\s*</div>",
      caseSensitive: false,
    );
    final qidPattern = RegExp(
      r'''<div\s+class=['"][^'"]*\bquestion-wrapper\b[^'"]*['"][^>]*\bdata-qid=['"]([^'"]+)['"]''',
      caseSensitive: false,
    );

    for (final groupMatch in groupPattern.allMatches(rawHtml)) {
      final groupHtml = groupMatch.group(1) ?? '';
      final contextMatch = contextPattern.firstMatch(groupHtml);
      if (contextMatch == null) {
        continue;
      }
      final contextText = _htmlToPlainText(contextMatch.group(1) ?? '');
      if (contextText.trim().isEmpty) {
        continue;
      }
      for (final qidMatch in qidPattern.allMatches(groupHtml)) {
        final qid = qidMatch.group(1);
        if (qid != null && qid.isNotEmpty) {
          result.putIfAbsent(qid, () => contextText);
        }
      }
    }

    return result;
  }

  static String _htmlToPlainText(String html) {
    var text = html
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</\s*div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
    return text.trim();
  }

  static String _examFromRoot(String root) {
    if (!root.startsWith('assets/')) {
      return 'TOEIC';
    }
    final segments = root.split('/');
    if (segments.length >= 3 &&
        segments[0] == 'assets' &&
        segments[1] == 'data') {
      return segments[2];
    }
    return 'TOEIC';
  }

  static String _yearFromRoot(String root) {
    if (!root.startsWith('assets/')) {
      final normalized = root.replaceAll('\\', '/');
      final idx = normalized.indexOf('/TOEIC/');
      if (idx != -1) {
        final sub = normalized.substring(idx + 7);
        final segs = sub.split('/');
        if (segs.isNotEmpty) {
          return segs[0];
        }
      }
      return 'Sample';
    }
    final segments = root.split('/');
    if (segments.length >= 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'data') {
      return segments[3];
    }
    return 'Sample';
  }

  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'\d+|\D+');
    final aParts = pattern
        .allMatches(a)
        .map((match) => match.group(0)!)
        .toList();
    final bParts = pattern
        .allMatches(b)
        .map((match) => match.group(0)!)
        .toList();
    final length = aParts.length < bParts.length
        ? aParts.length
        : bParts.length;

    for (var index = 0; index < length; index++) {
      final aNumber = int.tryParse(aParts[index]);
      final bNumber = int.tryParse(bParts[index]);
      final result = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : aParts[index].toLowerCase().compareTo(bParts[index].toLowerCase());
      if (result != 0) {
        return result;
      }
    }

    return aParts.length.compareTo(bParts.length);
  }
}

class TestSummary {
  final String root;
  final String title;
  final String exam;
  final String year;
  final int parts;
  final int questions;

  const TestSummary({
    required this.root,
    required this.title,
    required this.exam,
    required this.year,
    this.parts = 7,
    this.questions = 200,
  });
}

class TestLibraryPage extends StatefulWidget {
  const TestLibraryPage({super.key});

  @override
  State<TestLibraryPage> createState() => _TestLibraryPageState();
}

class _TestLibraryPageState extends State<TestLibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<TestSummary>> _testsFuture;

  @override
  void initState() {
    super.initState();
    _testsFuture = TestRepository.loadSummaries();
  }

  void _loadTests() {
    setState(() {
      _testsFuture = TestRepository.loadSummaries();
    });
  }

  static const List<String> _examTabs = [
    'Tất cả',
    'IELTS Academic',
    'IELTS General',
    'TOEIC SW',
    'TOEIC',
    'HSK 1',
    'HSK 2',
    'HSK 3',
    'HSK 4',
    'HSK 5',
    'HSK 6',
    'TOPIK II',
    'TOPIK I',
    'N5',
    'N4',
    'N3',
    'N2',
    'N1',
    'Digital SAT',
    'Tiếng Anh THPTQG',
    'Toán THPTQG',
    'Vật lý THPTQG',
    'Hóa học THPTQG',
    'Sinh học THPTQG',
    'ACT',
  ];

  static const List<String> _yearTabs = [
    '2024',
    '2023',
    '2022',
    '2021',
    '2020',
    '2019',
    '2018',
    'Sample',
  ];

  String _selectedExam = 'TOEIC';
  String _selectedYear = 'Sample';

  List<TestSummary> _filteredTests(List<TestSummary> tests) {
    final keyword = _searchController.text.trim().toLowerCase();
    return tests.where((test) {
      final matchesExam = test.exam == _selectedExam;
      final matchesYear = test.year == _selectedYear;
      final matchesKeyword =
          keyword.isEmpty || test.title.toLowerCase().contains(keyword);
      return matchesExam && matchesYear && matchesKeyword;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Study4Header(onRefresh: _loadTests),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 492),
                  child: FutureBuilder<List<TestSummary>>(
                    future: _testsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return LibraryLoadError(
                          error: snapshot.error.toString(),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final tests = _filteredTests(snapshot.data!);
                      return CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LibraryFilterTabs(
                                    examTabs: _examTabs,
                                    yearTabs: _yearTabs,
                                    selectedExam: _selectedExam,
                                    selectedYear: _selectedYear,
                                    onExamSelected: (value) =>
                                        setState(() => _selectedExam = value),
                                    onYearSelected: (value) =>
                                        setState(() => _selectedYear = value),
                                  ),
                                  const SizedBox(height: 16),
                                  LibrarySearchField(
                                    controller: _searchController,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.blue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                    onPressed: () => setState(() {}),
                                    child: const Text(
                                      'Tìm kiếm',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 20),
                            sliver: SliverLayoutBuilder(
                              builder: (context, constraints) {
                                return SliverGrid(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) =>
                                        TestSummaryCard(test: tests[index]),
                                    childCount: tests.length,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 14,
                                        crossAxisSpacing: 24,
                                        mainAxisExtent: 214,
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryFilterTabs extends StatelessWidget {
  final List<String> examTabs;
  final List<String> yearTabs;
  final String selectedExam;
  final String selectedYear;
  final ValueChanged<String> onExamSelected;
  final ValueChanged<String> onYearSelected;

  const LibraryFilterTabs({
    super.key,
    required this.examTabs,
    required this.yearTabs,
    required this.selectedExam,
    required this.selectedYear,
    required this.onExamSelected,
    required this.onYearSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LibraryDropdown(
          value: selectedExam,
          items: examTabs,
          hintText: 'Chọn kỳ thi',
          onChanged: onExamSelected,
        ),
        const SizedBox(height: 10),
        _LibraryDropdown(
          value: selectedYear,
          items: yearTabs,
          hintText: 'Chọn năm',
          onChanged: onYearSelected,
        ),
      ],
    );
  }
}

class _LibraryDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _LibraryDropdown({
    required this.value,
    required this.items,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = items.contains(value) ? value : items.first;

    return SizedBox(
      height: 40,
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isExpanded: true,
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Colors.black,
          size: 24,
        ),
        dropdownColor: Colors.white,
        style: const TextStyle(fontSize: 15, color: AppColors.text),
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: Color(0xFFB8C5D5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: AppColors.blue, width: 1.2),
          ),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<String>(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class LibrarySearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15, color: AppColors.text),
        decoration: InputDecoration(
          hintText:
              'Nhập từ khóa bạn muốn tìm kiếm: tên sách, dạng câu hỏi ...',
          hintStyle: const TextStyle(color: Color(0xFF8997AA), fontSize: 15),
          suffixIcon: const Icon(Icons.search, color: Colors.black, size: 24),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: Color(0xFFB8C5D5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: AppColors.blue, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class LibraryLoadError extends StatelessWidget {
  final String error;

  const LibraryLoadError({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Study4Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Không tải được danh sách đề',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                error,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TestSummaryCard extends StatelessWidget {
  final TestSummary test;

  const TestSummaryCard({super.key, required this.test});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            test.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF222222),
              fontSize: 16,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '${test.parts} phần thi | ${test.questions} câu hỏi',
            style: const TextStyle(
              color: Color(0xFF65758A),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                side: const BorderSide(color: AppColors.blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TestDetailPage(testRoot: test.root),
                  ),
                );
              },
              child: const Text(
                'Chi tiết',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TestDetailPage extends StatefulWidget {
  final String testRoot;

  const TestDetailPage({super.key, this.testRoot = defaultTestRoot});

  @override
  State<TestDetailPage> createState() => _TestDetailPageState();
}

class _TestDetailPageState extends State<TestDetailPage> {
  late final Future<TestData> _future = TestRepository.load(
    root: widget.testRoot,
  );
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<TestData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Study4Header(),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Study4Card(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Không tải được dữ liệu đề thi',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                snapshot.error.toString(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            if (!snapshot.hasData) {
              return const Column(
                children: [
                  Study4Header(),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }

            final data = snapshot.data!;
            return Column(
              children: [
                const Study4Header(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 492),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 28),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.blue,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back, size: 20),
                              label: const Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Study4Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SmallTag('#TOEIC'),
                                const SizedBox(height: 8),
                                Text(
                                  data.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                SegmentedTabs(
                                  labels: const [
                                    'Thông tin đề thi',
                                    'Đáp án/transcript',
                                  ],
                                  selectedIndex: _tab,
                                  onSelected: (index) =>
                                      setState(() => _tab = index),
                                ),
                                const SizedBox(height: 20),
                                if (_tab == 0)
                                  PracticeInfo(data: data)
                                else
                                  AnswerInfo(data: data),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum HeaderMenuAction { history, vocabList, vocabExport, importTests }

class Study4Header extends StatelessWidget {
  final VoidCallback? onRefresh;

  const Study4Header({super.key, this.onRefresh});

  static const Map<String, List<String>> _availableTestsByYear = {
    '2018': [
      'Practice Set TOEIC 2018 Test 1',
      'Practice Set TOEIC 2018 Test 2',
      'Practice Set TOEIC 2018 Test 3',
      'Practice Set TOEIC 2018 Test 4',
      'Practice Set TOEIC 2018 Test 5',
    ],
    '2019': [
      'Practice Set TOEIC 2019 Test 1',
      'Practice Set TOEIC 2019 Test 2',
      'Practice Set TOEIC 2019 Test 3',
      'Practice Set TOEIC 2019 Test 4',
      'Practice Set TOEIC 2019 Test 5',
      'Practice Set TOEIC 2019 Test 6',
      'Practice Set TOEIC 2019 Test 7',
      'Practice Set TOEIC 2019 Test 8',
      'Practice Set TOEIC 2019 Test 9',
      'Practice Set TOEIC 2019 Test 10',
    ],
    '2020': [
      'Practice Set TOEIC 2020 Test 1',
      'Practice Set TOEIC 2020 Test 2',
      'Practice Set TOEIC 2020 Test 3',
      'Practice Set TOEIC 2020 Test 4',
      'Practice Set TOEIC 2020 Test 5',
      'Practice Set TOEIC 2020 Test 6',
      'Practice Set TOEIC 2020 Test 7',
      'Practice Set TOEIC 2020 Test 8',
      'Practice Set TOEIC 2020 Test 9',
      'Practice Set TOEIC 2020 Test 10',
    ],
    '2021': [
      'Practice Set TOEIC 2021 Test 1',
      'Practice Set TOEIC 2021 Test 2',
      'Practice Set TOEIC 2021 Test 3',
      'Practice Set TOEIC 2021 Test 4',
      'Practice Set TOEIC 2021 Test 5',
    ],
    '2022': [
      'Practice Set TOEIC 2022 Test 1',
      'Practice Set TOEIC 2022 Test 2',
      'Practice Set TOEIC 2022 Test 3',
      'Practice Set TOEIC 2022 Test 4',
      'Practice Set TOEIC 2022 Test 5',
      'Practice Set TOEIC 2022 Test 6',
      'Practice Set TOEIC 2022 Test 7',
      'Practice Set TOEIC 2022 Test 8',
      'Practice Set TOEIC 2022 Test 9',
      'Practice Set TOEIC 2022 Test 10',
    ],
    '2023': [
      'Practice Set 2023 TOEIC Test 1',
      'Practice Set 2023 TOEIC Test 2',
      'Practice Set 2023 TOEIC Test 3',
      'Practice Set 2023 TOEIC Test 4',
      'Practice Set 2023 TOEIC Test 5',
      'Practice Set 2023 TOEIC Test 6',
      'Practice Set 2023 TOEIC Test 7',
      'Practice Set 2023 TOEIC Test 8',
      'Practice Set 2023 TOEIC Test 9',
      'Practice Set 2023 TOEIC Test 10',
    ],
    '2024': [
      '2024 Practice Set TOEIC Test 1',
      '2024 Practice Set TOEIC Test 2',
      '2024 Practice Set TOEIC Test 3',
      '2024 Practice Set TOEIC Test 4',
      '2024 Practice Set TOEIC Test 5',
      '2024 Practice Set TOEIC Test 6',
      '2024 Practice Set TOEIC Test 7',
      '2024 Practice Set TOEIC Test 8',
      '2024 Practice Set TOEIC Test 9',
      '2024 Practice Set TOEIC Test 10',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/toeic/logo/study4_new_logo_sm.png',
            width: 174,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                'STUDY4',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              );
            },
          ),
          const Spacer(),
          PopupMenuButton<HeaderMenuAction>(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.menu, size: 26, color: Colors.black),
                Positioned(
                  right: -6,
                  top: -7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE83B4B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '13',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            onSelected: (action) {
              _handleMenuAction(context, action);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: HeaderMenuAction.history,
                child: Row(
                  children: [
                    Icon(Icons.history, color: AppColors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Lịch sử kiểm tra'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: HeaderMenuAction.vocabList,
                child: Row(
                  children: [
                    Icon(Icons.book, color: AppColors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Danh sách từ vựng'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: HeaderMenuAction.vocabExport,
                child: Row(
                  children: [
                    Icon(Icons.share, color: AppColors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Export từ vựng'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: HeaderMenuAction.importTests,
                child: Row(
                  children: [
                    Icon(Icons.cloud_download, color: AppColors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Import bài kiểm tra'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, HeaderMenuAction action) {
    switch (action) {
      case HeaderMenuAction.history:
        _showHistoryDialog(context);
        break;
      case HeaderMenuAction.vocabList:
        _showVocabListDialog(context);
        break;
      case HeaderMenuAction.vocabExport:
        _showVocabExportDialog(context);
        break;
      case HeaderMenuAction.importTests:
        _showImportYearsDialog(context);
        break;
    }
  }

  void _showHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final history = TestHistoryManager.history;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history, color: AppColors.blue),
              SizedBox(width: 8),
              Text('Lịch sử kiểm tra'),
            ],
          ),
          content: history.isEmpty
              ? const SizedBox(
                  width: 320,
                  height: 100,
                  child: Center(child: Text('Chưa có lịch sử làm bài.')),
                )
              : SizedBox(
                  width: 400,
                  height: 350,
                  child: ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      final dateStr =
                          "${entry.submittedAt.day.toString().padLeft(2, '0')}/${entry.submittedAt.month.toString().padLeft(2, '0')}/${entry.submittedAt.year} ${entry.submittedAt.hour.toString().padLeft(2, '0')}:${entry.submittedAt.minute.toString().padLeft(2, '0')}";
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.testName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Thời gian: $dateStr',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Kết quả: ${entry.correctCount}/${entry.totalQuestions} câu đúng',
                                    style: const TextStyle(
                                      color: AppColors.blue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Thời gian làm: ${entry.timeSpent}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  void _showVocabListDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<String>>(
          future: VocabularyManager.getVocabularyFiles(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final files = snapshot.data!;
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.book, color: AppColors.blue),
                  SizedBox(width: 8),
                  Text('Danh sách file từ vựng'),
                ],
              ),
              content: files.isEmpty
                  ? const SizedBox(
                      width: 320,
                      height: 100,
                      child: Center(child: Text('Chưa có file từ vựng nào.')),
                    )
                  : SizedBox(
                      width: 350,
                      height: 300,
                      child: ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.description,
                              color: Colors.amber,
                            ),
                            title: Text(file),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _showFileWordsDialog(context, file);
                            },
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFileWordsDialog(BuildContext context, String filename) {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, String>>>(
          future: _loadFileWords(filename),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final words = snapshot.data!;
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  title: Row(
                    children: [
                      const Icon(Icons.book_outlined, color: AppColors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: const TextStyle(
                            fontSize: 16,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: words.isEmpty
                      ? const SizedBox(
                          width: 320,
                          height: 100,
                          child: Center(
                            child: Text('Không có từ vựng nào trong file này.'),
                          ),
                        )
                      : SizedBox(
                          width: 400,
                          height: 350,
                          child: ListView.builder(
                            itemCount: words.length,
                            itemBuilder: (context, index) {
                              final item = words[index];
                              final word = item['word'] ?? '';
                              final meaning = item['meaning'] ?? '';
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: Colors.white,
                                child: ListTile(
                                  title: Text(
                                    word,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(meaning),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () async {
                                      await _deleteWordFromFile(filename, word);
                                      final updated = await _loadFileWords(
                                        filename,
                                      );
                                      setStateDialog(() {
                                        words.clear();
                                        words.addAll(updated);
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showVocabListDialog(context);
                      },
                      child: const Text('Quay lại'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Đóng'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, String>>> _loadFileWords(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();
      final list = <Map<String, String>>[];
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          list.add({
            'word': parts[0].trim(),
            'meaning': parts.sublist(1).join(':').trim(),
          });
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error loading file words: $e');
      return [];
    }
  }

  Future<void> _deleteWordFromFile(String filename, String word) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final updatedLines = <String>[];
        for (final line in lines) {
          final parts = line.split(':');
          if (parts.isNotEmpty && parts[0].trim() == word) {
            continue; // skip this word
          }
          updatedLines.add(line);
        }
        await file.writeAsString(updatedLines.join('\n'));
      }
    } catch (e) {
      debugPrint('Error deleting word: $e');
    }
  }

  void _showVocabExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<String>>(
          future: VocabularyManager.getVocabularyFiles(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final files = snapshot.data!;
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.share, color: AppColors.blue),
                  SizedBox(width: 8),
                  Text('Export file từ vựng'),
                ],
              ),
              content: files.isEmpty
                  ? const SizedBox(
                      width: 320,
                      height: 100,
                      child: Center(
                        child: Text('Chưa có file từ vựng nào để export.'),
                      ),
                    )
                  : SizedBox(
                      width: 350,
                      height: 300,
                      child: ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.share,
                              color: AppColors.blue,
                            ),
                            title: Text(file),
                            trailing: const Icon(
                              Icons.ios_share,
                              size: 18,
                              color: AppColors.blue,
                            ),
                            onTap: () async {
                              Navigator.of(ctx).pop();
                              final dir =
                                  await getApplicationDocumentsDirectory();
                              final filePath = '${dir.path}/$file';
                              if (await File(filePath).exists()) {
                                await Share.shareXFiles(
                                  [XFile(filePath)],
                                  text:
                                      'Danh sách từ vựng $file từ ứng dụng STUDY4 Clone',
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImportYearsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final years = ['2018', '2019', '2020', '2021', '2022', '2023', '2024'];
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_download, color: AppColors.blue),
              SizedBox(width: 8),
              Text('Chọn năm thi để import'),
            ],
          ),
          content: SizedBox(
            width: 320,
            height: 350,
            child: ListView.builder(
              itemCount: years.length,
              itemBuilder: (context, index) {
                final year = years[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_today,
                      color: AppColors.blue,
                    ),
                    title: Text(
                      'TOEIC $year',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showImportTestsDialog(context, year);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
          ],
        );
      },
    );
  }

  void _showImportTestsDialog(BuildContext context, String year) {
    final tests = _availableTestsByYear[year] ?? [];
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<bool>>(
          future: Future.wait(
            tests.map((testName) async {
              final docDir = await getApplicationDocumentsDirectory();
              final infoFile = File(
                '${docDir.path}/TOEIC/$year/$testName/test_info.json',
              );
              return await infoFile.exists();
            }),
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final isDownloadedList = snapshot.data!;
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.folder_open, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Text('Bài thi năm $year'),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 350,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: tests.length,
                        itemBuilder: (context, index) {
                          final testName = tests[index];
                          final isDownloaded = isDownloadedList[index];
                          return ListTile(
                            leading: Icon(
                              isDownloaded
                                  ? Icons.check_circle
                                  : Icons.download_for_offline,
                              color: isDownloaded
                                  ? Colors.green
                                  : AppColors.blue,
                            ),
                            title: Text(
                              testName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isDownloaded
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: isDownloaded
                                    ? Colors.grey
                                    : Colors.black,
                              ),
                            ),
                            onTap: isDownloaded
                                ? null
                                : () async {
                                    Navigator.of(ctx).pop();
                                    final success = await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) =>
                                          DownloadProgressDialog(
                                            year: year,
                                            testNames: [testName],
                                          ),
                                    );
                                    if (success == true) {
                                      if (onRefresh != null) {
                                        onRefresh!();
                                      }
                                    }
                                  },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Tải tất cả các đề chưa tải'),
                      onPressed: () async {
                        final toDownload = <String>[];
                        for (int i = 0; i < tests.length; i++) {
                          if (!isDownloadedList[i]) {
                            toDownload.add(tests[i]);
                          }
                        }
                        if (toDownload.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tất cả các đề đã được tải về.'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop();
                        final success = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => DownloadProgressDialog(
                            year: year,
                            testNames: toDownload,
                          ),
                        );
                        if (success == true) {
                          if (onRefresh != null) {
                            onRefresh!();
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showImportYearsDialog(context);
                  },
                  child: const Text('Quay lại'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class Study4Card extends StatelessWidget {
  final Widget child;

  const Study4Card({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 1.5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SmallTag extends StatelessWidget {
  final String text;

  const SmallTag(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.chip,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.black),
      ),
    );
  }
}

class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : 8,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(index),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedIndex == index
                        ? AppColors.paleBlue
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: selectedIndex == index
                          ? AppColors.blue
                          : Colors.black,
                      fontWeight: selectedIndex == index
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PracticeInfo extends StatefulWidget {
  final TestData data;

  const PracticeInfo({super.key, required this.data});

  @override
  State<PracticeInfo> createState() => _PracticeInfoState();
}

class _PracticeInfoState extends State<PracticeInfo> {
  final Set<int> _selectedPartNumbers = {};
  final List<int> _timeOptions = List.generate(24, (index) => (index + 1) * 5);
  int _detailTab = 1;
  int? _selectedTimeLimit;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.access_time, size: 18, color: Colors.black),
            Text(
              'Thời gian làm bài: 120 phút | ${data.parts.length} phần thi | ${data.totalQuestions} câu hỏi |',
            ),
            const Text('4264 bình luận'),
            const Icon(Icons.group, size: 18, color: Colors.black),
            const Text('3639759 người đã luyện tập đề thi này'),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Chú ý: đề được quy đổi sang scaled score (ví dụ trên thang điểm 990 cho TOEIC hoặc 9.0 cho IELTS), vui lòng chọn chế độ làm FULL TEST.',
          style: TextStyle(
            color: Color(0xFFFF3143),
            fontStyle: FontStyle.italic,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 46),
        DetailNavTabs(
          selectedIndex: _detailTab,
          onSelected: (index) => setState(() => _detailTab = index),
        ),
        const SizedBox(height: 22),
        if (_detailTab == 0)
          _PracticeTabContent(
            data: data,
            selectedPartNumbers: _selectedPartNumbers,
            selectedTimeLimit: _selectedTimeLimit,
            timeOptions: _timeOptions,
            onPartChanged: (partNumber, selected) {
              setState(() {
                if (selected) {
                  _selectedPartNumbers.add(partNumber);
                } else {
                  _selectedPartNumbers.remove(partNumber);
                }
              });
            },
            onTimeChanged: (value) =>
                setState(() => _selectedTimeLimit = value),
          )
        else
          FullTestTab(data: data),
      ],
    );
  }
}

class DetailNavTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const DetailNavTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Luyện tập', 'Làm full test'];
    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                child: _UnderlinedTab(
                  labels[index],
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

class _UnderlinedTab extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _UnderlinedTab(
    this.text, {
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: selected
              ? const Border(
                  bottom: BorderSide(color: AppColors.blue, width: 2),
                )
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? AppColors.blue : AppColors.muted,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PracticeTabContent extends StatelessWidget {
  final TestData data;
  final Set<int> selectedPartNumbers;
  final List<int> timeOptions;
  final int? selectedTimeLimit;
  final void Function(int partNumber, bool selected) onPartChanged;
  final ValueChanged<int?> onTimeChanged;

  const _PracticeTabContent({
    required this.data,
    required this.selectedPartNumbers,
    required this.timeOptions,
    required this.selectedTimeLimit,
    required this.onPartChanged,
    required this.onTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 14),
          decoration: BoxDecoration(
            color: AppColors.greenPanel,
            border: Border.all(color: const Color(0xFFC8EBD8)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.greenText,
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pro tips: Hình thức luyện tập từng phần và chọn mức thời gian phù hợp sẽ giúp bạn tập trung vào giải đúng các câu hỏi thay vì phải chịu áp lực hoàn thành bài thi.',
                  style: TextStyle(
                    color: AppColors.greenText,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Chọn phần thi bạn muốn làm',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 10),
        for (final part in data.parts)
          PartPracticeOption(
            part: part,
            selected: selectedPartNumbers.contains(part.meta.number),
            onChanged: (selected) => onPartChanged(part.meta.number, selected),
          ),
        const SizedBox(height: 18),
        const Text(
          'Giới hạn thời gian (Để trống để làm bài không giới hạn)',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 10),
        Container(
          height: 39,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFB8C5D5)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedTimeLimit,
              isExpanded: true,
              icon: const Icon(
                Icons.unfold_more,
                color: Color(0xFF7A8EA8),
                size: 20,
              ),
              dropdownColor: Colors.white,
              menuMaxHeight: 520,
              hint: const Text(
                '-- Chọn thời gian --',
                style: TextStyle(color: Color(0xFF6B7C93), fontSize: 16),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text(
                    '-- Chọn thời gian --',
                    style: TextStyle(color: Color(0xFF6B7C93), fontSize: 16),
                  ),
                ),
                ...timeOptions.map(
                  (minute) => DropdownMenuItem<int>(
                    value: minute,
                    child: Text(
                      '$minute phút',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
              onChanged: onTimeChanged,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PracticeQuestionsPage(
                data: data,
                selectedPartNumbers: selectedPartNumbers,
                timeLimitMinutes: selectedTimeLimit,
              ),
            ),
          ),
          child: const Text(
            'LUYỆN TẬP',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class FullTestTab extends StatelessWidget {
  final TestData data;

  const FullTestTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 13, 16, 13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2DE),
            border: Border.all(color: const Color(0xFFF5DBAC)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFF9A650F), size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sẵn sàng để bắt đầu làm full test? Để đạt được kết quả tốt nhất, bạn cần dành ra 120 phút cho bài test này.',
                  style: TextStyle(
                    color: Color(0xFF9A650F),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PracticeQuestionsPage(data: data, timeLimitMinutes: 120),
            ),
          ),
          child: const Text(
            'BẮT ĐẦU THI',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class PartPracticeOption extends StatelessWidget {
  final PartData part;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const PartPracticeOption({
    super.key,
    required this.part,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 22,
            child: Checkbox(
              value: selected,
              onChanged: (value) => onChanged(value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Color(0xFF777777), width: .8),
              activeColor: AppColors.blue,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(!selected),
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '${part.meta.label} (${part.questions.length} câu hỏi)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnswerInfo extends StatelessWidget {
  final TestData data;

  const AnswerInfo({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.blue,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TranscriptPage(data: data)),
            ),
            child: const Text(
              'Xem đáp án đề thi',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 26),
          const Text('Các phần thi:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          for (var index = 0; index < data.parts.length; index++)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 5),
              child: Row(
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 17)),
                  Text(
                    '${data.parts[index].meta.label}: ',
                    style: const TextStyle(fontSize: 16),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TranscriptPage(data: data, initialPart: index),
                      ),
                    ),
                    child: const Text(
                      'Đáp án',
                      style: TextStyle(color: AppColors.blue, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TranscriptPage extends StatefulWidget {
  final TestData data;
  final int initialPart;

  const TranscriptPage({super.key, required this.data, this.initialPart = 0});

  @override
  State<TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends State<TranscriptPage> {
  late int _selectedPart = widget.initialPart;
  bool _showTranscript = true;

  @override
  Widget build(BuildContext context) {
    final part = widget.data.parts[_selectedPart];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Study4Header(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 492),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Đáp án/transcript: ${widget.data.name}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(56, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                side: const BorderSide(color: AppColors.blue),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Thoát',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Study4Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PracticePartTabs(
                              parts: widget.data.parts,
                              selectedIndex: _selectedPart,
                              onSelected: (index) =>
                                  setState(() => _selectedPart = index),
                            ),
                            const SizedBox(height: 18),
                            ..._buildAnswerBlocks(part),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAnswerBlocks(PartData part) {
    final widgets = <Widget>[];
    final shownImages = <String>{};

    for (final question in part.questions) {
      for (final image in question.imageFiles) {
        final path = '${widget.data.root}/${part.meta.folder}/$image';
        if (shownImages.add(path)) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SafeAssetImage(path: path),
            ),
          );
        }
      }

      widgets.add(
        AnswerRow(
          testName: widget.data.name,
          partFolder: part.meta.folder,
          question: question,
          showTranscript: _showTranscript,
        ),
      );
      widgets.add(const SizedBox(height: 10));
    }

    if (widgets.isNotEmpty) {
      widgets.insert(
        0,
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.blue,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => setState(() => _showTranscript = !_showTranscript),
          icon: Icon(
            _showTranscript ? Icons.arrow_drop_down : Icons.arrow_right,
            size: 20,
          ),
          label: Text(
            _showTranscript ? 'Ẩn Transcript' : 'Hiện Transcript',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return widgets;
  }
}

class AnswerRow extends StatefulWidget {
  final String testName;
  final String partFolder;
  final ToeicQuestion question;
  final bool showTranscript;

  const AnswerRow({
    super.key,
    required this.testName,
    required this.partFolder,
    required this.question,
    required this.showTranscript,
  });

  @override
  State<AnswerRow> createState() => _AnswerRowState();
}

class _AnswerRowState extends State<AnswerRow> {
  @override
  Widget build(BuildContext context) {
    final questionKey = getHighlightKey(
      testName: widget.testName,
      partFolder: widget.partFolder,
      questionNumber: widget.question.number,
      qid: widget.question.qid,
      component: 'question',
    );
    final transcriptKey = getHighlightKey(
      testName: widget.testName,
      partFolder: widget.partFolder,
      questionNumber: widget.question.number,
      qid: widget.question.qid,
      component: 'transcript',
    );
    final answerKey = getHighlightKey(
      testName: widget.testName,
      partFolder: widget.partFolder,
      questionNumber: widget.question.number,
      qid: widget.question.qid,
      component: 'correct_answer',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.paleBlue,
              child: Text(
                '${widget.question.number}',
                style: const TextStyle(color: AppColors.blue, fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: HighlightableText(
                  text: 'Đáp án đúng: ${widget.question.answer}',
                  enabled: true,
                  marks: HighlightManager.getHighlights(answerKey),
                  onChanged: (marks) {
                    setState(() {
                      HighlightManager.setHighlights(answerKey, marks);
                    });
                  },
                  style: const TextStyle(
                    color: Color(0xFF20A856),
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.showTranscript &&
            widget.question.transcript.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 8, 0, 0),
            child: HighlightableText(
              text: widget.question.transcript,
              enabled: true,
              marks: HighlightManager.getHighlights(transcriptKey),
              onChanged: (marks) {
                setState(() {
                  HighlightManager.setHighlights(transcriptKey, marks);
                });
              },
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.text,
              ),
            ),
          ),
        if (widget.question.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 8, 0, 0),
            child: HighlightableText(
              text: widget.question.text,
              enabled: true,
              marks: HighlightManager.getHighlights(questionKey),
              onChanged: (marks) {
                setState(() {
                  HighlightManager.setHighlights(questionKey, marks);
                });
              },
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

class PracticeQuestionsPage extends StatefulWidget {
  final TestData data;
  final Set<int>? selectedPartNumbers;
  final int? timeLimitMinutes;

  const PracticeQuestionsPage({
    super.key,
    required this.data,
    this.selectedPartNumbers,
    this.timeLimitMinutes,
  });

  @override
  State<PracticeQuestionsPage> createState() => _PracticeQuestionsPageState();
}

class _PracticeQuestionsPageState extends State<PracticeQuestionsPage> {
  final Map<String, String> _answers = {};
  final Set<String> _reviewQuestionKeys = {};
  final Map<String, List<TextHighlightMark>> _contentHighlights = {};
  final Map<String, GlobalKey> _questionKeys = {};
  final ScrollController _pageScrollController = ScrollController();
  final GlobalKey _pageViewportKey = GlobalKey();
  final GlobalKey _questionAreaKey = GlobalKey();
  late final List<PartData> _visibleParts;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  Duration _remaining = Duration.zero;
  Map<String, String>? _savedAnswers;
  Set<String>? _savedReviewQuestionKeys;
  String? _focusedQuestionKey;
  int _selectedPartIndex = 0;
  bool _submitted = false;
  bool _highlightEnabled = true;
  bool _showResultAnswers = false;

  @override
  void initState() {
    super.initState();
    _visibleParts = widget.selectedPartNumbers == null
        ? widget.data.parts
        : widget.data.parts
              .where(
                (part) =>
                    widget.selectedPartNumbers!.contains(part.meta.number),
              )
              .toList();
    if (widget.timeLimitMinutes != null) {
      _remaining = Duration(minutes: widget.timeLimitMinutes!);
    }
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageScrollController.dispose();
    PracticeAudioBar.stopActive();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _submitted) {
        return;
      }
      if (widget.timeLimitMinutes == null) {
        setState(() {
          _elapsed += const Duration(seconds: 1);
        });
        return;
      }

      if (_remaining > Duration.zero) {
        setState(() {
          _remaining -= const Duration(seconds: 1);
          if (_remaining < Duration.zero) {
            _remaining = Duration.zero;
          }
        });
        if (_remaining == Duration.zero) {
          _submit();
        }
      }
    });
  }

  void _selectPart(int index) {
    if (index < 0 ||
        index >= _visibleParts.length ||
        index == _selectedPartIndex) {
      return;
    }
    PracticeAudioBar.stopActive();
    setState(() {
      _selectedPartIndex = index;
      _focusedQuestionKey = null;
    });
  }

  String _questionKey(PartData part, ToeicQuestion question) {
    final id = question.qid.trim().isNotEmpty ? question.qid.trim() : 'no-qid';
    return '${part.meta.folder}::${question.number}::$id';
  }

  List<TextHighlightMark> _highlightsFor(
    PartData part,
    ToeicQuestion question, {
    String? suffix,
  }) {
    final key = getHighlightKey(
      testName: widget.data.name,
      partFolder: part.meta.folder,
      questionNumber: question.number,
      qid: question.qid,
      component: suffix ?? 'question',
    );
    return HighlightManager.getHighlights(key);
  }

  void _setQuestionHighlights(
    PartData part,
    ToeicQuestion question,
    List<TextHighlightMark> highlights, {
    String? suffix,
  }) {
    final key = getHighlightKey(
      testName: widget.data.name,
      partFolder: part.meta.folder,
      questionNumber: question.number,
      qid: question.qid,
      component: suffix ?? 'question',
    );
    setState(() {
      HighlightManager.setHighlights(key, highlights);
    });
  }

  void _toggleReview(PartData part, ToeicQuestion question) {
    final key = _questionKey(part, question);
    setState(() {
      if (!_reviewQuestionKeys.add(key)) {
        _reviewQuestionKeys.remove(key);
      }
    });
  }

  GlobalKey _questionWidgetKeyFor(PartData part, ToeicQuestion question) {
    return _questionKeys.putIfAbsent(
      _questionKey(part, question),
      GlobalKey.new,
    );
  }

  void _jumpToQuestion(PartData part, ToeicQuestion question) {
    final targetKey = _questionKey(part, question);
    final partIndex = _visibleParts.indexWhere(
      (item) => item.meta.folder == part.meta.folder,
    );
    if (partIndex == -1) {
      return;
    }

    PracticeAudioBar.stopActive();

    // Scroll to top immediately so question area is in viewport
    if (_pageScrollController.hasClients) {
      _pageScrollController.jumpTo(0);
    }

    setState(() {
      _selectedPartIndex = partIndex;
      _focusedQuestionKey = targetKey;
    });

    _scrollToQuestionWhenReady(targetKey);
  }

  void _scrollToQuestionWhenReady(String targetKey, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _focusedQuestionKey != targetKey) {
        return;
      }

      final globalKey = _questionKeys[targetKey];
      final ctx = globalKey?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
        return;
      }

      if (attempt < 8 && mounted && _focusedQuestionKey == targetKey) {
        await Future<void>.delayed(Duration(milliseconds: 60 + attempt * 60));
        if (mounted && _focusedQuestionKey == targetKey) {
          _scrollToQuestionWhenReady(targetKey, attempt: attempt + 1);
        }
      }
    });
  }

  void _saveOrRestoreProgress() {
    if (_savedAnswers == null) {
      setState(() {
        _savedAnswers = Map<String, String>.from(_answers);
        _savedReviewQuestionKeys = Set<String>.from(_reviewQuestionKeys);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu tạm bài làm hiện tại.')),
      );
      return;
    }

    setState(() {
      _answers
        ..clear()
        ..addAll(_savedAnswers!);
      _reviewQuestionKeys
        ..clear()
        ..addAll(_savedReviewQuestionKeys ?? const <String>{});
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã khôi phục bài làm đã lưu.')),
    );
  }

  void _submit() {
    if (_submitted) {
      return;
    }
    _timer?.cancel();
    PracticeAudioBar.stopActive();

    // Save to test history
    try {
      final total = _visibleParts.expand((p) => p.questions).length;
      final correct = _visibleParts
          .expand((p) => p.questions)
          .where(_isCorrect)
          .length;
      final timeSpentText = _formatTimer(_completionDuration);

      TestHistoryManager.addEntry(
        TestHistoryEntry(
          testName: widget.data.name,
          submittedAt: DateTime.now(),
          correctCount: correct,
          totalQuestions: total,
          timeSpent: timeSpentText,
        ),
      );
    } catch (e) {
      debugPrint('Error recording test history: $e');
    }

    setState(() {
      _submitted = true;
      _showResultAnswers = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageScrollController.hasClients) {
        _pageScrollController.jumpTo(0);
      }
    });
  }

  String _formatTimer(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  bool _isCorrect(ToeicQuestion question) {
    return _answers[question.qid] == question.answer;
  }

  bool _isSkipped(ToeicQuestion question) {
    return !_answers.containsKey(question.qid);
  }

  int _correctCountFor(Iterable<ToeicQuestion> questions) {
    return questions.where(_isCorrect).length;
  }

  int _wrongCountFor(Iterable<ToeicQuestion> questions) {
    return questions
        .where((question) => !_isSkipped(question) && !_isCorrect(question))
        .length;
  }

  int _skippedCountFor(Iterable<ToeicQuestion> questions) {
    return questions.where(_isSkipped).length;
  }

  Duration get _completionDuration {
    if (widget.timeLimitMinutes == null) {
      return _elapsed;
    }
    final limit = Duration(minutes: widget.timeLimitMinutes!);
    final used = limit - _remaining;
    return used.isNegative ? Duration.zero : used;
  }

  void _retryWrongQuestions() {
    final wrongParts = <int>{};
    for (final part in _visibleParts) {
      if (part.questions.any(
        (question) => !_isSkipped(question) && !_isCorrect(question),
      )) {
        wrongParts.add(part.meta.number);
      }
    }
    if (wrongParts.isEmpty) {
      return;
    }

    setState(() {
      _answers.removeWhere((qid, _) {
        return _visibleParts
            .expand((part) => part.questions)
            .any((question) => question.qid == qid && !_isCorrect(question));
      });
      _submitted = false;
      _showResultAnswers = false;
      _selectedPartIndex = _visibleParts.indexWhere(
        (part) => wrongParts.contains(part.meta.number),
      );
      if (_selectedPartIndex < 0) {
        _selectedPartIndex = 0;
      }
    });
  }

  void _showAnswerDetail(PartData part, ToeicQuestion question) {
    showDialog<void>(
      context: context,
      builder: (context) => AnswerDetailDialog(
        data: widget.data,
        part: part,
        question: question,
        selectedAnswer: _answers[question.qid],
      ),
    );
  }

  Widget _buildResultPage() {
    final allQuestions = _visibleParts
        .expand((part) => part.questions)
        .toList();
    final total = allQuestions.length;
    final correct = _correctCountFor(allQuestions);
    final wrong = _wrongCountFor(allQuestions);
    final skipped = _skippedCountFor(allQuestions);
    final accuracy = total == 0 ? 0.0 : correct * 100 / total;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Study4Header(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 492),
                  child: ListView(
                    key: _pageViewportKey,
                    controller: _pageScrollController,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                    children: [
                      Text(
                        'Kết quả luyện tập: ${widget.data.name}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final part in _visibleParts)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFAD3B),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                part.meta.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _showResultAnswers = true),
                            child: const Text(
                              'Xem đáp án',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text,
                              side: const BorderSide(color: AppColors.blue),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Quay về trang đề thi'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ResultSummaryPanel(
                        correct: correct,
                        wrong: wrong,
                        skipped: skipped,
                        total: total,
                        accuracy: accuracy,
                        durationText: _formatTimer(_completionDuration),
                      ),
                      const SizedBox(height: 22),
                      _ResultCountCards(
                        correct: correct,
                        wrong: wrong,
                        skipped: skipped,
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Phân tích chi tiết',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PracticePartTabs(
                        parts: _visibleParts,
                        selectedIndex: _selectedPartIndex,
                        onSelected: (index) =>
                            setState(() => _selectedPartIndex = index),
                      ),
                      const SizedBox(height: 14),
                      _ResultAnalysisTable(
                        parts: [_visibleParts[_selectedPartIndex]],
                        answers: _answers,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Đáp án',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              side: const BorderSide(color: AppColors.blue),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            onPressed: () => setState(
                              () => _showResultAnswers = !_showResultAnswers,
                            ),
                            child: Text(
                              _showResultAnswers
                                  ? 'Ẩn chi tiết đáp án'
                                  : 'Xem chi tiết đáp án',
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              side: const BorderSide(color: AppColors.blue),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            onPressed: wrong > 0 ? _retryWrongQuestions : null,
                            child: const Text('Làm lại các câu sai'),
                          ),
                          const Text(
                            'Chú ý: Khi làm lại các câu sai, điểm trung bình của bạn sẽ KHÔNG BỊ ẢNH HƯỞNG.',
                            style: TextStyle(
                              color: Color(0xFFFF3143),
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDF5E7),
                          border: Border.all(color: const Color(0xFFC8EBD8)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Tips: Khi xem chi tiết đáp án, bạn có thể tạo và lưu highlight từ vựng, keywords và tạo note để học và tra cứu khi có nhu cầu ôn lại đề thi này trong tương lai.',
                          style: TextStyle(
                            color: AppColors.greenText,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ),
                      if (_showResultAnswers) ...[
                        const SizedBox(height: 22),
                        _ResultAnswerList(
                          parts: _visibleParts,
                          answers: _answers,
                          onDetail: _showAnswerDetail,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_visibleParts.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Study4Header(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Không có phần thi nào để hiển thị.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: AppColors.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedPartIndex >= _visibleParts.length) {
      _selectedPartIndex = _visibleParts.length - 1;
    }
    if (_submitted) {
      return _buildResultPage();
    }
    final activePart = _visibleParts[_selectedPartIndex];
    final answeredCount = _visibleParts
        .expand((part) => part.questions)
        .where((question) => _answers.containsKey(question.qid))
        .length;
    final totalCount = _visibleParts.fold(
      0,
      (sum, part) => sum + part.questions.length,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Study4Header(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 492),
                  child: ListView(
                    key: _pageViewportKey,
                    controller: _pageScrollController,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              widget.data.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2F55B7),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Thoát',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        key: _questionAreaKey,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HighlightToggleRow(
                              enabled: _highlightEnabled,
                              onChanged: (value) =>
                                  setState(() => _highlightEnabled = value),
                            ),
                            const SizedBox(height: 16),
                            if (_visibleParts.length > 1) ...[
                              PracticePartTabs(
                                parts: _visibleParts,
                                selectedIndex: _selectedPartIndex,
                                onSelected: _selectPart,
                              ),
                              const SizedBox(height: 22),
                            ] else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.paleBlue,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  activePart.meta.label,
                                  style: const TextStyle(
                                    color: AppColors.blue,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                            ],
                            PartPracticeContent(
                              root: widget.data.root,
                              part: activePart,
                              answers: _answers,
                              reviewedQuestionKeys: _reviewQuestionKeys,
                              focusedQuestionKey: _focusedQuestionKey,
                              highlightEnabled: _highlightEnabled,
                              submitted: _submitted,
                              questionKeyFor: _questionWidgetKeyFor,
                              questionStateKey: _questionKey,
                              highlightsFor: _highlightsFor,
                              onHighlightsChanged: _setQuestionHighlights,
                              onToggleReview: _toggleReview,
                              onAnswer: (question, answer) {
                                if (_submitted) {
                                  return;
                                }
                                setState(() {
                                  _answers[question.qid] = answer;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      PracticeSubmitPanel(
                        parts: _visibleParts,
                        answered: answeredCount,
                        total: totalCount,
                        timerText: _formatTimer(
                          widget.timeLimitMinutes == null
                              ? _elapsed
                              : _remaining,
                        ),
                        isCountdown: widget.timeLimitMinutes != null,
                        submitted: _submitted,
                        answeredQuestionIds: _answers.keys.toSet(),
                        reviewedQuestionKeys: _reviewQuestionKeys,
                        focusedQuestionKey: _focusedQuestionKey,
                        questionStateKey: _questionKey,
                        savedProgressAvailable: _savedAnswers != null,
                        onSubmit: _submit,
                        onSaveOrRestore: _saveOrRestoreProgress,
                        onQuestionTap: _jumpToQuestion,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HighlightToggleRow extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const HighlightToggleRow({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(
          value: enabled,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeColor: Colors.white,
          activeTrackColor: AppColors.blue,
        ),
        const SizedBox(width: 6),
        const Text(
          'Highlight nội dung',
          style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message:
              'Bôi đen text để highlight nội dung. Bạn có thể thay đổi màu sắc hoặc thêm ghi chú.',
          child: const Icon(Icons.info_outline, size: 15, color: Colors.black),
        ),
      ],
    );
  }
}

class _ResultSummaryPanel extends StatelessWidget {
  final int correct;
  final int wrong;
  final int skipped;
  final int total;
  final double accuracy;
  final String durationText;

  const _ResultSummaryPanel({
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.total,
    required this.accuracy,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _summaryRow(Icons.check, 'Kết quả làm bài', '$correct/$total'),
          const SizedBox(height: 18),
          _summaryRow(
            Icons.gps_fixed,
            'Độ chính xác (#đúng/#tổng)',
            '${accuracy.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 18),
          _summaryRow(Icons.schedule, 'Thời gian hoàn thành', durationText),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.text),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, color: AppColors.text),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _ResultCountCards extends StatelessWidget {
  final int correct;
  final int wrong;
  final int skipped;

  const _ResultCountCards({
    required this.correct,
    required this.wrong,
    required this.skipped,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _card(
            Icons.check_circle,
            const Color(0xFF42B875),
            'Trả lời đúng',
            correct,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _card(
            Icons.cancel,
            const Color(0xFFE94B55),
            'Trả lời sai',
            wrong,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _card(
            Icons.remove_circle,
            const Color(0xFF7C8FA6),
            'Bỏ qua',
            skipped,
          ),
        ),
      ],
    );
  }

  Widget _card(IconData icon, Color color, String label, int count) {
    return Container(
      height: 152,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'câu hỏi',
            style: TextStyle(fontSize: 14, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

class _ResultAnalysisTable extends StatelessWidget {
  final List<PartData> parts;
  final Map<String, String> answers;

  const _ResultAnalysisTable({required this.parts, required this.answers});

  @override
  Widget build(BuildContext context) {
    final rows = <_AnalysisRow>[
      for (final part in parts) _AnalysisRow.fromPart(part, answers),
    ];
    final totalQuestions = rows.fold(0, (sum, row) => sum + row.total);
    final totalCorrect = rows.fold(0, (sum, row) => sum + row.correct);
    final totalWrong = rows.fold(0, (sum, row) => sum + row.wrong);
    final totalSkipped = rows.fold(0, (sum, row) => sum + row.skipped);
    final totalAccuracy = totalQuestions == 0
        ? 0.0
        : totalCorrect * 100 / totalQuestions;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 620,
          child: Column(
            children: [
              _analysisHeader(),
              const Divider(height: 1, color: AppColors.border),
              for (final row in rows) _analysisRow(row),
              _analysisRow(
                _AnalysisRow(
                  label: 'Total',
                  total: totalQuestions,
                  correct: totalCorrect,
                  wrong: totalWrong,
                  skipped: totalSkipped,
                  accuracy: totalAccuracy,
                ),
                shaded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _analysisHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: const Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(
              'Phân loại câu hỏi',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              'Số câu đúng',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              'Số câu sai',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Số câu bỏ qua',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Độ chính xác',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Danh sách câu',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analysisRow(_AnalysisRow row, {bool shaded = false}) {
    return Container(
      color: shaded ? const Color(0xFFF6F7F9) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(
              row.label,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text('${row.correct}', textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 70,
            child: Text('${row.wrong}', textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 80,
            child: Text('${row.skipped}', textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${row.accuracy.toStringAsFixed(2)}%',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF4A55)),
                ),
                child: Text(
                  '${row.wrong}',
                  style: const TextStyle(
                    color: Color(0xFFFF4A55),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisRow {
  final String label;
  final int total;
  final int correct;
  final int wrong;
  final int skipped;
  final double accuracy;

  const _AnalysisRow({
    required this.label,
    required this.total,
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.accuracy,
  });

  factory _AnalysisRow.fromPart(PartData part, Map<String, String> answers) {
    final total = part.questions.length;
    final correct = part.questions
        .where((question) => answers[question.qid] == question.answer)
        .length;
    final skipped = part.questions
        .where((question) => !answers.containsKey(question.qid))
        .length;
    final wrong = total - correct - skipped;
    final accuracy = total == 0 ? 0.0 : correct * 100 / total;
    return _AnalysisRow(
      label: '[${part.meta.label}] ${_partDescription(part)}',
      total: total,
      correct: correct,
      wrong: wrong,
      skipped: skipped,
      accuracy: accuracy,
    );
  }

  static String _partDescription(PartData part) {
    final firstText = part.questions
        .map((question) => question.text.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    if (firstText.isEmpty) {
      return part.meta.number == 1 ? 'Tranh tả người và vật' : part.meta.label;
    }
    return firstText.length > 38
        ? '${firstText.substring(0, 38)}...'
        : firstText;
  }
}

class _ResultAnswerList extends StatelessWidget {
  final List<PartData> parts;
  final Map<String, String> answers;
  final void Function(PartData part, ToeicQuestion question) onDetail;

  const _ResultAnswerList({
    required this.parts,
    required this.answers,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in parts) ...[
          Text(
            part.meta.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            children: [
              for (final question in part.questions)
                SizedBox(
                  width: 200,
                  child: _ResultAnswerItem(
                    question: question,
                    selectedAnswer: answers[question.qid],
                    onDetail: () => onDetail(part, question),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class _ResultAnswerItem extends StatelessWidget {
  final ToeicQuestion question;
  final String? selectedAnswer;
  final VoidCallback onDetail;

  const _ResultAnswerItem({
    required this.question,
    required this.selectedAnswer,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final isSkipped = selectedAnswer == null;
    final isCorrect = selectedAnswer == question.answer;
    final statusColor = isSkipped
        ? const Color(0xFF7C8FA6)
        : (isCorrect ? const Color(0xFF20A856) : const Color(0xFFE83B4B));
    final statusIcon = isSkipped
        ? Icons.remove
        : (isCorrect ? Icons.check : Icons.close);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.paleBlue,
          child: Text(
            '${question.number}',
            style: const TextStyle(
              color: AppColors.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${selectedAnswer ?? '-'}: ${question.answer}',
          style: const TextStyle(fontSize: 14, color: AppColors.text),
        ),
        const SizedBox(width: 4),
        Icon(statusIcon, size: 16, color: statusColor),
        const SizedBox(width: 6),
        InkWell(
          onTap: onDetail,
          child: const Text(
            '[Chi tiết]',
            style: TextStyle(color: AppColors.blue, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class AnswerDetailDialog extends StatefulWidget {
  final TestData data;
  final PartData part;
  final ToeicQuestion question;
  final String? selectedAnswer;

  const AnswerDetailDialog({
    super.key,
    required this.data,
    required this.part,
    required this.question,
    required this.selectedAnswer,
  });

  @override
  State<AnswerDetailDialog> createState() => _AnswerDetailDialogState();
}

class _AnswerDetailDialogState extends State<AnswerDetailDialog> {
  bool _showTranscript = false;

  @override
  void dispose() {
    PracticeAudioBar.stopActive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final options = _optionsFor(question, widget.part.meta.number);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Đáp án chi tiết #${question.number}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  children: [
                    Text(
                      widget.data.name,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '#[${widget.part.meta.label}] ${_AnalysisRow._partDescription(widget.part)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (question.audioFiles.isNotEmpty) ...[
                      PracticeAudioBar(
                        audioPath:
                            '${widget.data.root}/${widget.part.meta.folder}/${question.audioFiles.first}',
                      ),
                      const SizedBox(height: 18),
                    ],
                    for (final image in question.imageFiles) ...[
                      SafeAssetImage(
                        path:
                            '${widget.data.root}/${widget.part.meta.folder}/$image',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (question.contextText.trim().isNotEmpty) ...[
                      ReadingPassageCard(text: question.contextText.trim()),
                      const SizedBox(height: 6),
                    ],
                    if (question.text.trim().isNotEmpty) ...[
                      HighlightableText(
                        text: question.text,
                        enabled: true,
                        marks: HighlightManager.getHighlights(
                          getHighlightKey(
                            testName: widget.data.name,
                            partFolder: widget.part.meta.folder,
                            questionNumber: question.number,
                            qid: question.qid,
                            component: 'question',
                          ),
                        ),
                        onChanged: (marks) {
                          setState(() {
                            HighlightManager.setHighlights(
                              getHighlightKey(
                                testName: widget.data.name,
                                partFolder: widget.part.meta.folder,
                                questionNumber: question.number,
                                qid: question.qid,
                                component: 'question',
                              ),
                              marks,
                            );
                          });
                        },
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.paleBlue,
                          child: Text(
                            '${question.number}',
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in options.entries)
                                _DetailOptionRow(
                                  label: entry.key,
                                  text: entry.value,
                                  selected: widget.selectedAnswer == entry.key,
                                  correct: question.answer == entry.key,
                                  testName: widget.data.name,
                                  partFolder: widget.part.meta.folder,
                                  questionNumber: question.number,
                                  qid: question.qid,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Đáp án đúng: ${question.answer}',
                                style: const TextStyle(
                                  color: Color(0xFF20A856),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.blue,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          setState(() => _showTranscript = !_showTranscript),
                      icon: Icon(
                        _showTranscript
                            ? Icons.arrow_drop_down
                            : Icons.arrow_right,
                        size: 20,
                      ),
                      label: Text(
                        _showTranscript
                            ? 'Ẩn giải thích chi tiết đáp án'
                            : 'Giải thích chi tiết đáp án',
                      ),
                    ),
                    if (_showTranscript) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: HighlightableText(
                          text: question.transcript.trim().isEmpty
                              ? 'Chưa có transcript/giải thích cho câu này.'
                              : question.transcript,
                          enabled: true,
                          marks: HighlightManager.getHighlights(
                            getHighlightKey(
                              testName: widget.data.name,
                              partFolder: widget.part.meta.folder,
                              questionNumber: question.number,
                              qid: question.qid,
                              component: 'transcript',
                            ),
                          ),
                          onChanged: (marks) {
                            setState(() {
                              HighlightManager.setHighlights(
                                getHighlightKey(
                                  testName: widget.data.name,
                                  partFolder: widget.part.meta.folder,
                                  questionNumber: question.number,
                                  qid: question.qid,
                                  component: 'transcript',
                                ),
                                marks,
                              );
                            });
                          },
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _optionsFor(ToeicQuestion question, int partNumber) {
    final nonEmpty = Map.fromEntries(
      question.options.entries.where((entry) => entry.value.trim().isNotEmpty),
    );
    if (nonEmpty.isNotEmpty) {
      return nonEmpty;
    }
    final labels = partNumber == 2
        ? const ['A', 'B', 'C']
        : const ['A', 'B', 'C', 'D'];
    return {for (final label in labels) label: ''};
  }
}

class _DetailOptionRow extends StatefulWidget {
  final String label;
  final String text;
  final bool selected;
  final bool correct;

  final String testName;
  final String partFolder;
  final int questionNumber;
  final String qid;

  const _DetailOptionRow({
    required this.label,
    required this.text,
    required this.selected,
    required this.correct,
    required this.testName,
    required this.partFolder,
    required this.questionNumber,
    required this.qid,
  });

  @override
  State<_DetailOptionRow> createState() => _DetailOptionRowState();
}

class _DetailOptionRowState extends State<_DetailOptionRow> {
  @override
  Widget build(BuildContext context) {
    final wrongSelected = widget.selected && !widget.correct;
    final color = widget.correct
        ? const Color(0xFF20A856)
        : (wrongSelected ? const Color(0xFFE83B4B) : const Color(0xFF6B7280));
    final key = getHighlightKey(
      testName: widget.testName,
      partFolder: widget.partFolder,
      questionNumber: widget.questionNumber,
      qid: widget.qid,
      component: 'option_${widget.label}',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: widget.correct
            ? const Color(0xFFEAF8EF)
            : (wrongSelected ? const Color(0xFFFFF1F2) : Colors.white),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            widget.selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: HighlightableText(
              text: widget.text.trim().isEmpty
                  ? widget.label
                  : '${widget.label}. ${widget.text}',
              enabled: true,
              marks: HighlightManager.getHighlights(key),
              onChanged: (marks) {
                setState(() {
                  HighlightManager.setHighlights(key, marks);
                });
              },
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: widget.correct || wrongSelected ? color : AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PracticePartTabs extends StatefulWidget {
  final List<PartData> parts;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const PracticePartTabs({
    super.key,
    required this.parts,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<PracticePartTabs> createState() => _PracticePartTabsState();
}

class _PracticePartTabsState extends State<PracticePartTabs> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) {
      return;
    }

    final current = _controller.offset;
    final target = (current + event.scrollDelta.dy + event.scrollDelta.dx)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if (target != current) {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SizedBox(
          height: 34,
          width: double.infinity,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            child: Row(
              children: [
                for (var index = 0; index < widget.parts.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == widget.parts.length - 1 ? 0 : 8,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onSelected(index),
                      child: Container(
                        height: 32,
                        constraints: const BoxConstraints(minWidth: 90),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 17),
                        decoration: BoxDecoration(
                          color: index == widget.selectedIndex
                              ? AppColors.paleBlue
                              : const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.parts[index].meta.label,
                          style: TextStyle(
                            color: index == widget.selectedIndex
                                ? AppColors.blue
                                : const Color(0xFF4B5563),
                            fontSize: 15,
                            fontWeight: index == widget.selectedIndex
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HighlightableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool enabled;
  final List<TextHighlightMark> marks;
  final ValueChanged<List<TextHighlightMark>> onChanged;
  final VoidCallback? onTap;

  const HighlightableText({
    super.key,
    required this.text,
    required this.style,
    required this.enabled,
    required this.marks,
    required this.onChanged,
    this.onTap,
  });

  @override
  State<HighlightableText> createState() => _HighlightableTextState();
}

class _HighlightableTextState extends State<HighlightableText> {
  static const _colors = [
    Color(0xFF9CECF4),
    Color(0xFFF7B7C6),
    Color(0xFFCFF4C8),
    Color(0xFFFFF59D),
  ];

  TextSelection? _selection;
  OverlayEntry? _toolbarEntry;
  ({int start, int end})? _savedRange;

  @override
  void didUpdateWidget(covariant HighlightableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _selection = null;
      _removeToolbar();
    }
  }

  @override
  void dispose() {
    _removeToolbar();
    super.dispose();
  }

  void _removeToolbar() {
    _toolbarEntry?.remove();
    _toolbarEntry?.dispose();
    _toolbarEntry = null;
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _selection = selection;
    if (selection.isValid && !selection.isCollapsed) {
      _savedRange = _selectedRange();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _savedRange != null) {
          _showToolbarOverlay();
        }
      });
    } else {
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final sel = _selection;
        if (sel == null || !sel.isValid || sel.isCollapsed) {
          _removeToolbar();
        }
      });
    }
  }

  void _showToolbarOverlay() {
    _removeToolbar();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final overlay = Overlay.of(context);
    _toolbarEntry = OverlayEntry(
      builder: (ctx) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize || !box.attached) {
          return const SizedBox.shrink();
        }
        final topLeft = box.localToGlobal(Offset.zero);
        final screenSize = MediaQuery.of(ctx).size;
        const toolbarWidth = 260.0;
        const toolbarHeight = 40.0;
        final left = (topLeft.dx + box.size.width / 2 - toolbarWidth / 2).clamp(
          8.0,
          screenSize.width - toolbarWidth - 8,
        );
        final top = (topLeft.dy - toolbarHeight - 6).clamp(
          8.0,
          screenSize.height - toolbarHeight - 8,
        );

        return Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF333333),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final color in _colors)
                    _ToolbarColorButton(
                      color: color,
                      onPressed: () {
                        _applyFromSaved(color: color);
                      },
                    ),
                  _ToolbarIconButton(
                    icon: Icons.strikethrough_s,
                    tooltip: 'Gạch ngang',
                    onPressed: () {
                      _applyFromSaved(strikeThrough: true);
                    },
                  ),
                  _ToolbarIconButton(
                    icon: Icons.edit,
                    tooltip: 'Thêm ghi chú',
                    onPressed: _addNoteFromSaved,
                  ),
                  _ToolbarIconButton(
                    icon: Icons.add,
                    tooltip: 'Thêm từ vựng',
                    onPressed: _addVocabularyFromSaved,
                  ),
                  _ToolbarIconButton(
                    icon: Icons.delete,
                    tooltip: 'Xóa highlight',
                    onPressed: _clearFromSaved,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_toolbarEntry!);
  }

  void _applyFromSaved({
    Color? color,
    bool strikeThrough = false,
    String? note,
  }) {
    final range = _savedRange;
    if (range == null) return;
    final updated = [...widget.marks]
      ..removeWhere((mark) => mark.overlaps(range.start, range.end))
      ..add(
        TextHighlightMark(
          start: range.start,
          end: range.end,
          color: color,
          strikeThrough: strikeThrough,
          note: note,
        ),
      )
      ..sort((a, b) => a.start.compareTo(b.start));
    widget.onChanged(updated);
    _removeToolbar();
  }

  void _clearFromSaved() {
    final range = _savedRange;
    if (range == null) return;
    widget.onChanged(
      widget.marks
          .where((mark) => !mark.overlaps(range.start, range.end))
          .toList(),
    );
    _removeToolbar();
  }

  Future<void> _addNoteFromSaved() async {
    final range = _savedRange;
    if (range == null) return;
    _removeToolbar();
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm ghi chú'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Nhập ghi chú ngắn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || note == null) return;
    final updated = [...widget.marks]
      ..removeWhere((mark) => mark.overlaps(range.start, range.end))
      ..add(
        TextHighlightMark(
          start: range.start,
          end: range.end,
          color: const Color(0xFFF7B7C6),
          note: note.trim().isEmpty ? null : note.trim(),
        ),
      )
      ..sort((a, b) => a.start.compareTo(b.start));
    widget.onChanged(updated);
  }

  Future<void> _addVocabularyFromSaved() async {
    final range = _savedRange;
    if (range == null) return;
    final selectedText = widget.text.substring(range.start, range.end);
    _removeToolbar();

    final meaning = await showDialog<String>(
      context: context,
      builder: (ctx) => AddVocabularyDialog(initialWord: selectedText),
    );

    if (meaning != null && meaning.isNotEmpty && mounted) {
      final updated = [...widget.marks]
        ..removeWhere((mark) => mark.overlaps(range.start, range.end))
        ..add(
          TextHighlightMark(
            start: range.start,
            end: range.end,
            color: const Color(0xFFFFF59D), // default soft yellow
            note: null,
          ),
        )
        ..sort((a, b) => a.start.compareTo(b.start));
      widget.onChanged(updated);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã lưu từ vựng: "$selectedText" vào file txt và highlight.',
          ),
          backgroundColor: const Color(0xFF20A856),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final span = _buildSpan(includeNotes: true);
    if (!widget.enabled) {
      return RichText(text: span);
    }

    return SelectableText.rich(
      span,
      onSelectionChanged: _onSelectionChanged,
      onTap: widget.onTap,
    );
  }

  TextSpan _buildSpan({required bool includeNotes}) {
    final marks = [...widget.marks]
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });
    final children = <InlineSpan>[];
    var cursor = 0;

    for (final mark in marks) {
      final start = mark.start.clamp(0, widget.text.length).toInt();
      final end = mark.end.clamp(0, widget.text.length).toInt();
      if (start >= end || start < cursor) {
        continue;
      }
      if (cursor < start) {
        children.add(TextSpan(text: widget.text.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: widget.text.substring(start, end),
          style: TextStyle(
            backgroundColor: mark.color?.withOpacity(.65),
            decoration: mark.strikeThrough ? TextDecoration.lineThrough : null,
            decorationColor: AppColors.text,
            decorationThickness: 1.7,
          ),
        ),
      );
      if (includeNotes && mark.note != null && mark.note!.trim().isNotEmpty) {
        children.add(
          TextSpan(
            text: ' ${mark.note!.trim()}',
            style: const TextStyle(
              color: Color(0xFFFF4A55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      cursor = end;
    }

    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return TextSpan(style: widget.style, children: children);
  }

  ({int start, int end})? _selectedRange() {
    final selection = _selection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      return null;
    }
    final base = selection.baseOffset.clamp(0, widget.text.length).toInt();
    final extent = selection.extentOffset.clamp(0, widget.text.length).toInt();
    final start = base < extent ? base : extent;
    final end = base < extent ? extent : base;
    if (start >= end) {
      return null;
    }
    return (start: start, end: end);
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(icon, size: 18),
        color: Colors.white,
        onPressed: onPressed,
      ),
    );
  }
}

class _ToolbarColorButton extends StatelessWidget {
  final Color color;
  final VoidCallback onPressed;

  const _ToolbarColorButton({required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tô màu',
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 34,
          alignment: Alignment.center,
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class PracticeSubmitPanel extends StatelessWidget {
  final int answered;
  final int total;
  final List<PartData> parts;
  final String timerText;
  final bool isCountdown;
  final bool submitted;
  final Set<String> answeredQuestionIds;
  final Set<String> reviewedQuestionKeys;
  final String? focusedQuestionKey;
  final String Function(PartData part, ToeicQuestion question) questionStateKey;
  final bool savedProgressAvailable;
  final VoidCallback onSubmit;
  final VoidCallback onSaveOrRestore;
  final void Function(PartData part, ToeicQuestion question) onQuestionTap;

  const PracticeSubmitPanel({
    super.key,
    required this.answered,
    required this.total,
    required this.parts,
    required this.timerText,
    required this.isCountdown,
    required this.submitted,
    required this.answeredQuestionIds,
    required this.reviewedQuestionKeys,
    required this.focusedQuestionKey,
    required this.questionStateKey,
    required this.savedProgressAvailable,
    required this.onSubmit,
    required this.onSaveOrRestore,
    required this.onQuestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: isCountdown ? 'Thời gian còn lại: ' : 'Thời gian làm bài: ',
              children: [
                TextSpan(
                  text: timerText,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 39,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.blue, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: submitted ? null : onSubmit,
              child: Text(
                submitted ? 'ĐÃ NỘP BÀI' : 'NỘP BÀI',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: onSaveOrRestore,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                savedProgressAvailable
                    ? 'Khôi phục bài làm đã lưu ❯'
                    : 'Lưu bài làm hiện tại ❯',
                style: const TextStyle(
                  color: Color(0xFFFF4A55),
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Chú ý: bạn có thể click vào số thứ tự câu hỏi trong bài để đánh dấu review',
            style: TextStyle(
              color: Color(0xFFFF9D22),
              fontSize: 14,
              height: 1.35,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Đã làm $answered/$total câu',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          for (final part in parts) ...[
            Text(
              part.meta.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 7,
              children: [
                for (final question in part.questions)
                  InkWell(
                    onTap: () => onQuestionTap(part, question),
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      width: 32,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _questionColor(part, question),
                        border: Border.all(
                          color: _questionBorderColor(part, question),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${question.number}',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              _isFocused(part, question) ||
                                  _isReviewed(part, question) ||
                                  answeredQuestionIds.contains(question.qid)
                              ? Colors.white
                              : const Color(0xFF333333),
                          fontWeight:
                              _isFocused(part, question) ||
                                  _isReviewed(part, question) ||
                                  answeredQuestionIds.contains(question.qid)
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  bool _isFocused(PartData part, ToeicQuestion question) {
    return focusedQuestionKey == questionStateKey(part, question);
  }

  bool _isReviewed(PartData part, ToeicQuestion question) {
    return reviewedQuestionKeys.contains(questionStateKey(part, question));
  }

  Color _questionColor(PartData part, ToeicQuestion question) {
    if (_isFocused(part, question)) {
      return AppColors.blue;
    }
    if (answeredQuestionIds.contains(question.qid)) {
      return AppColors.blue;
    }
    if (_isReviewed(part, question)) {
      return const Color(0xFFFF9D22);
    }
    return Colors.white;
  }

  Color _questionBorderColor(PartData part, ToeicQuestion question) {
    if (_isFocused(part, question)) {
      return AppColors.blue;
    }
    if (answeredQuestionIds.contains(question.qid)) {
      return AppColors.blue;
    }
    if (_isReviewed(part, question)) {
      return const Color(0xFFFF9D22);
    }
    return const Color(0xFFCCCCCC);
  }
}

class PartPracticeContent extends StatelessWidget {
  final String root;
  final PartData part;
  final Map<String, String> answers;
  final Set<String> reviewedQuestionKeys;
  final String? focusedQuestionKey;
  final bool highlightEnabled;
  final bool submitted;
  final GlobalKey Function(PartData part, ToeicQuestion question)
  questionKeyFor;
  final String Function(PartData part, ToeicQuestion question) questionStateKey;
  final List<TextHighlightMark> Function(
    PartData part,
    ToeicQuestion question, {
    String? suffix,
  })
  highlightsFor;
  final void Function(
    PartData part,
    ToeicQuestion question,
    List<TextHighlightMark> highlights, {
    String? suffix,
  })
  onHighlightsChanged;
  final void Function(PartData part, ToeicQuestion question) onToggleReview;
  final void Function(ToeicQuestion question, String answer) onAnswer;

  const PartPracticeContent({
    super.key,
    required this.root,
    required this.part,
    required this.answers,
    required this.reviewedQuestionKeys,
    required this.focusedQuestionKey,
    required this.highlightEnabled,
    required this.submitted,
    required this.questionKeyFor,
    required this.questionStateKey,
    required this.highlightsFor,
    required this.onHighlightsChanged,
    required this.onToggleReview,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupsForPart(part);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups)
          PracticeQuestionGroup(
            root: root,
            part: part,
            questions: group,
            answers: answers,
            reviewedQuestionKeys: reviewedQuestionKeys,
            focusedQuestionKey: focusedQuestionKey,
            highlightEnabled: highlightEnabled,
            submitted: submitted,
            questionKeyFor: questionKeyFor,
            questionStateKey: questionStateKey,
            highlightsFor: highlightsFor,
            onHighlightsChanged: onHighlightsChanged,
            onToggleReview: onToggleReview,
            onAnswer: onAnswer,
          ),
      ],
    );
  }

  List<List<ToeicQuestion>> _groupsForPart(PartData part) {
    if (part.meta.number == 3 || part.meta.number == 4) {
      final groups = <String, List<ToeicQuestion>>{};
      for (final question in part.questions) {
        final key = question.audioFiles.isNotEmpty
            ? question.audioFiles.first
            : 'q-${question.number}';
        groups.putIfAbsent(key, () => []).add(question);
      }
      return groups.values.toList();
    }

    if (part.meta.number == 6 || part.meta.number == 7) {
      final contextGroups = <List<ToeicQuestion>>[];
      var currentContext = '';
      var currentGroup = <ToeicQuestion>[];
      for (final question in part.questions) {
        final context = question.contextText.trim();
        if (currentGroup.isNotEmpty &&
            context.isNotEmpty &&
            context != currentContext) {
          contextGroups.add(currentGroup);
          currentGroup = <ToeicQuestion>[];
        }
        currentContext = context;
        currentGroup.add(question);
      }
      if (currentGroup.isNotEmpty) {
        contextGroups.add(currentGroup);
      }
      if (contextGroups.length > 1 ||
          contextGroups.any(
            (group) => group.first.contextText.trim().isNotEmpty,
          )) {
        return contextGroups;
      }

      final groups = <List<ToeicQuestion>>[];
      for (var index = 0; index < part.questions.length; index += 4) {
        groups.add(part.questions.skip(index).take(4).toList());
      }
      return groups;
    }

    return [
      for (final question in part.questions) [question],
    ];
  }
}

class PracticeQuestionGroup extends StatelessWidget {
  final String root;
  final PartData part;
  final List<ToeicQuestion> questions;
  final Map<String, String> answers;
  final Set<String> reviewedQuestionKeys;
  final String? focusedQuestionKey;
  final bool highlightEnabled;
  final bool submitted;
  final GlobalKey Function(PartData part, ToeicQuestion question)
  questionKeyFor;
  final String Function(PartData part, ToeicQuestion question) questionStateKey;
  final List<TextHighlightMark> Function(
    PartData part,
    ToeicQuestion question, {
    String? suffix,
  })
  highlightsFor;
  final void Function(
    PartData part,
    ToeicQuestion question,
    List<TextHighlightMark> highlights, {
    String? suffix,
  })
  onHighlightsChanged;
  final void Function(PartData part, ToeicQuestion question) onToggleReview;
  final void Function(ToeicQuestion question, String answer) onAnswer;

  const PracticeQuestionGroup({
    super.key,
    required this.root,
    required this.part,
    required this.questions,
    required this.answers,
    required this.reviewedQuestionKeys,
    required this.focusedQuestionKey,
    required this.highlightEnabled,
    required this.submitted,
    required this.questionKeyFor,
    required this.questionStateKey,
    required this.highlightsFor,
    required this.onHighlightsChanged,
    required this.onToggleReview,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final first = questions.first;
    final contextText = questions
        .map((question) => question.contextText.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    final images = <String>{};
    for (final question in questions) {
      images.addAll(question.imageFiles);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (first.audioFiles.isNotEmpty) ...[
            PracticeAudioBar(
              audioPath: '$root/${part.meta.folder}/${first.audioFiles.first}',
            ),
            const SizedBox(height: 20),
          ],
          for (final image in images)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SafeAssetImage(path: '$root/${part.meta.folder}/$image'),
            ),
          if ((part.meta.number == 6 || part.meta.number == 7) &&
              images.isEmpty) ...[
            if (contextText.isNotEmpty)
              ReadingPassageCard(text: contextText)
            else
              const ReadingPlaceholder(),
          ],
          for (final question in questions)
            PracticeQuestionCard(
              questionKey: questionKeyFor(part, question),
              partNumber: part.meta.number,
              question: question,
              selectedAnswer: answers[question.qid],
              reviewed: reviewedQuestionKeys.contains(
                questionStateKey(part, question),
              ),
              focused: focusedQuestionKey == questionStateKey(part, question),
              highlightEnabled: highlightEnabled,
              highlightsFor: (suffix) =>
                  highlightsFor(part, question, suffix: suffix),
              onHighlightsChanged: (marks, suffix) =>
                  onHighlightsChanged(part, question, marks, suffix: suffix),
              submitted: submitted,
              onToggleReview: () => onToggleReview(part, question),
              onAnswer: (answer) => onAnswer(question, answer),
            ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class PracticeAudioBar extends StatefulWidget {
  final String audioPath;
  const PracticeAudioBar({super.key, required this.audioPath});

  static AudioPlayer? activePlayer;

  static Future<void> stopActive() async {
    try {
      await activePlayer?.stop();
    } catch (_) {
      // Ignore stale player errors while switching parts.
    } finally {
      activePlayer = null;
    }
  }

  @override
  State<PracticeAudioBar> createState() => _PracticeAudioBarState();
}

class _PracticeAudioBarState extends State<PracticeAudioBar> {
  AudioPlayer? _audioPlayer;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _canPlay = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  Future<AudioPlayer?> _ensurePlayer() async {
    if (_audioPlayer != null) {
      return _audioPlayer;
    }

    try {
      setState(() => _isLoading = true);
      final player = AudioPlayer();
      _audioPlayer = player;

      _durationSubscription = player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });

      _positionSubscription = player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });

      _stateSubscription = player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      _completeSubscription = player.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _isPlaying = false;
          });
        }
      });

      String cleanPath = widget.audioPath;
      if (cleanPath.startsWith('assets/')) {
        cleanPath = cleanPath.substring('assets/'.length);
        await player.setSource(AssetSource(cleanPath));
      } else {
        await player.setSource(DeviceFileSource(cleanPath));
      }
      await player.setVolume(_volume);
      return player;
    } catch (e) {
      debugPrint('Error loading audio: $e');
      await _disposePlayer();
      if (mounted) {
        setState(() {
          _canPlay = false;
          _isPlaying = false;
        });
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    if (PracticeAudioBar.activePlayer == _audioPlayer) {
      PracticeAudioBar.activePlayer = null;
    }
    _disposePlayer();
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _completeSubscription?.cancel();
    _durationSubscription = null;
    _positionSubscription = null;
    _stateSubscription = null;
    _completeSubscription = null;

    final player = _audioPlayer;
    _audioPlayer = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('Error disposing audio: $e');
      }
    }
  }

  Future<void> _togglePlay() async {
    if (!_canPlay || _isLoading) {
      return;
    }

    try {
      final player = await _ensurePlayer();
      if (player == null) {
        return;
      }

      if (_isPlaying) {
        await player.pause();
      } else {
        if (PracticeAudioBar.activePlayer != player) {
          await PracticeAudioBar.activePlayer?.pause();
          PracticeAudioBar.activePlayer = player;
        }
        await player.resume();
      }
    } catch (e) {
      debugPrint('Error toggling audio: $e');
      if (mounted) {
        setState(() {
          _canPlay = false;
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _seek(double value) async {
    if (!_canPlay) {
      return;
    }
    final player = _audioPlayer;
    if (player == null) {
      return;
    }
    final position = Duration(milliseconds: value.toInt());
    try {
      await player.seek(position);
    } catch (e) {
      debugPrint('Error seeking audio: $e');
    }
  }

  Future<void> _setVolume(double value) async {
    setState(() {
      _volume = value;
      _isMuted = value == 0;
    });
    try {
      await _audioPlayer?.setVolume(value);
    } catch (e) {
      debugPrint('Error setting volume: $e');
    }
  }

  Future<void> _toggleMute() async {
    if (_isMuted) {
      setState(() {
        _isMuted = false;
        _volume = 1.0;
      });
      try {
        await _audioPlayer?.setVolume(1.0);
      } catch (e) {
        debugPrint('Error unmuting audio: $e');
      }
    } else {
      setState(() {
        _isMuted = true;
        _volume = 0.0;
      });
      try {
        await _audioPlayer?.setVolume(0.0);
      } catch (e) {
        debugPrint('Error muting audio: $e');
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.toDouble();
    final validMax = totalMs > 0 ? totalMs : 1.0;
    final validVal = posMs <= validMax ? posMs : validMax;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              _canPlay
                  ? (_isLoading
                        ? Icons.hourglass_empty
                        : (_isPlaying ? Icons.pause : Icons.play_arrow))
                  : Icons.volume_off,
              color: _canPlay ? const Color(0xFF4B5D78) : AppColors.muted,
              size: 28,
            ),
            onPressed: _canPlay && !_isLoading ? _togglePlay : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: const Color(0xFFD5DADF),
                inactiveTrackColor: const Color(0xFFE5E7EB),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                  pressedElevation: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                min: 0.0,
                max: validMax,
                value: validVal,
                onChanged: (val) {
                  _seek(val);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(_position),
            style: const TextStyle(fontSize: 14, color: AppColors.text),
          ),
          const SizedBox(width: 12),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              _isMuted || _volume == 0
                  ? Icons.volume_mute
                  : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up),
              color: const Color(0xFF4B5D78),
              size: 21,
            ),
            onPressed: _toggleMute,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: const Color(0xFF00A3E8),
                inactiveTrackColor: const Color(0xFFD5DADF),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                  pressedElevation: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                min: 0.0,
                max: 1.0,
                value: _volume,
                onChanged: (val) {
                  _setVolume(val);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.settings, color: Color(0xFF4B5D78), size: 21),
        ],
      ),
    );
  }
}

class ReadingPlaceholder extends StatelessWidget {
  const ReadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Đọc đoạn văn/biểu mẫu bên dưới và chọn đáp án đúng cho từng câu.',
        style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
      ),
    );
  }
}

class ReadingPassageCard extends StatelessWidget {
  final String text;

  const ReadingPassageCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      color: const Color(0xFFF5F6F8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, height: 1.52, color: Colors.black),
      ),
    );
  }
}

class SafeAssetImage extends StatelessWidget {
  final String path;

  const SafeAssetImage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading image asset: $path - $error');
          return _buildErrorWidget();
        },
      );
    } else {
      return Image.file(
        File(path),
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading image file: $path - $error');
          return _buildErrorWidget();
        },
      );
    }
  }

  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Không tải được hình ảnh của câu hỏi này.',
        style: TextStyle(fontSize: 14, height: 1.35, color: AppColors.muted),
      ),
    );
  }
}

class PracticeQuestionCard extends StatefulWidget {
  final GlobalKey questionKey;
  final int partNumber;
  final ToeicQuestion question;
  final String? selectedAnswer;
  final bool reviewed;
  final bool focused;
  final bool highlightEnabled;
  final List<TextHighlightMark> Function(String suffix) highlightsFor;
  final bool submitted;
  final void Function(List<TextHighlightMark> marks, String suffix)
  onHighlightsChanged;
  final VoidCallback onToggleReview;
  final ValueChanged<String> onAnswer;

  const PracticeQuestionCard({
    super.key,
    required this.questionKey,
    required this.partNumber,
    required this.question,
    required this.selectedAnswer,
    required this.reviewed,
    required this.focused,
    required this.highlightEnabled,
    required this.highlightsFor,
    required this.submitted,
    required this.onHighlightsChanged,
    required this.onToggleReview,
    required this.onAnswer,
  });

  @override
  State<PracticeQuestionCard> createState() => _PracticeQuestionCardState();
}

class _PracticeQuestionCardState extends State<PracticeQuestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant PracticeQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flash yellow border when review is toggled ON
    if (widget.reviewed && !oldWidget.reviewed) {
      _flashController.reverse(from: 1.0);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _optionsForQuestion();
    final hasQuestionText = widget.question.text.trim().isNotEmpty;

    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, child) {
        final flashOpacity = _flashController.value;
        final showFlash = flashOpacity > 0.01;
        final framePadding = (showFlash || widget.focused)
            ? const EdgeInsets.all(2)
            : EdgeInsets.zero;
        BoxDecoration? frameDecoration;
        if (widget.focused) {
          frameDecoration = BoxDecoration(
            border: Border.all(color: AppColors.blue, width: 1.2),
          );
        } else if (showFlash) {
          frameDecoration = BoxDecoration(
            border: Border.all(
              color: const Color(0xFFFF9D22).withOpacity(flashOpacity),
            ),
          );
        }

        if (!hasQuestionText) {
          // Side-by-side layout for empty question text (Part 1, Part 2)
          return Container(
            key: widget.questionKey,
            margin: const EdgeInsets.only(bottom: 12),
            padding: framePadding,
            decoration: frameDecoration,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QuestionNumberBadge(
                  number: widget.question.number,
                  reviewed: widget.reviewed,
                  focused: widget.focused,
                  onTap: widget.onToggleReview,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in options.entries)
                        PracticeOptionTile(
                          label: entry.key,
                          text: entry.value,
                          selected: widget.selectedAnswer == entry.key,
                          isCorrect:
                              widget.submitted &&
                              widget.question.answer == entry.key,
                          isWrong:
                              widget.submitted &&
                              widget.selectedAnswer == entry.key &&
                              widget.question.answer != entry.key,
                          onTap: () => widget.onAnswer(entry.key),
                          highlightEnabled: widget.highlightEnabled,
                          marks: widget.highlightsFor('option_${entry.key}'),
                          onHighlightsChanged: (marks) =>
                              widget.onHighlightsChanged(
                                marks,
                                'option_${entry.key}',
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Standard stacked layout for questions with text (Part 3, 4, 5, 6, 7)
          return Container(
            key: widget.questionKey,
            margin: const EdgeInsets.only(bottom: 14),
            padding: framePadding,
            decoration: frameDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QuestionNumberBadge(
                      number: widget.question.number,
                      reviewed: widget.reviewed,
                      focused: widget.focused,
                      onTap: widget.onToggleReview,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: HighlightableText(
                          text: widget.question.text,
                          enabled: widget.highlightEnabled,
                          marks: widget.highlightsFor('question'),
                          onChanged: (marks) =>
                              widget.onHighlightsChanged(marks, 'question'),
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in options.entries)
                        PracticeOptionTile(
                          label: entry.key,
                          text: entry.value,
                          selected: widget.selectedAnswer == entry.key,
                          isCorrect:
                              widget.submitted &&
                              widget.question.answer == entry.key,
                          isWrong:
                              widget.submitted &&
                              widget.selectedAnswer == entry.key &&
                              widget.question.answer != entry.key,
                          onTap: () => widget.onAnswer(entry.key),
                          highlightEnabled: widget.highlightEnabled,
                          marks: widget.highlightsFor('option_${entry.key}'),
                          onHighlightsChanged: (marks) =>
                              widget.onHighlightsChanged(
                                marks,
                                'option_${entry.key}',
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Map<String, String> _optionsForQuestion() {
    final nonEmpty = Map.fromEntries(
      widget.question.options.entries.where(
        (entry) => entry.value.trim().isNotEmpty,
      ),
    );
    if (nonEmpty.isNotEmpty) {
      return nonEmpty;
    }
    final labels = widget.partNumber == 2
        ? const ['A', 'B', 'C']
        : const ['A', 'B', 'C', 'D'];
    return {for (final label in labels) label: ''};
  }
}

class _QuestionNumberBadge extends StatelessWidget {
  final int number;
  final bool reviewed;
  final bool focused;
  final VoidCallback onTap;

  const _QuestionNumberBadge({
    required this.number,
    required this.reviewed,
    required this.focused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = reviewed || focused;
    final color = reviewed
        ? const Color(0xFFFF9D22)
        : (focused ? AppColors.blue : AppColors.paleBlue);

    return Tooltip(
      message: reviewed ? 'Bỏ đánh dấu review' : 'Đánh dấu review',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            '$number',
            style: TextStyle(
              color: active ? Colors.white : AppColors.blue,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class PracticeOptionTile extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback onTap;
  final bool highlightEnabled;
  final List<TextHighlightMark> marks;
  final ValueChanged<List<TextHighlightMark>> onHighlightsChanged;

  const PracticeOptionTile({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
    required this.highlightEnabled,
    required this.marks,
    required this.onHighlightsChanged,
  });

  @override
  Widget build(BuildContext context) {
    Color background = Colors.white;
    if (isCorrect) {
      background = const Color(0xFFEAF8EF);
    } else if (isWrong) {
      background = const Color(0xFFFFF1F2);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isCorrect
                  ? const Color(0xFF20A856)
                  : isWrong
                  ? const Color(0xFFE83B4B)
                  : (selected ? AppColors.blue : const Color(0xFF6B7280)),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: HighlightableText(
                text: text.trim().isEmpty ? label : '$label. $text',
                enabled: highlightEnabled,
                marks: marks,
                onChanged: onHighlightsChanged,
                onTap: onTap,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuestionPreview extends StatelessWidget {
  final String root;
  final PartData part;
  final ToeicQuestion question;

  const QuestionPreview({
    super.key,
    required this.root,
    required this.part,
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final image in question.imageFiles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SafeAssetImage(path: '$root/${part.meta.folder}/$image'),
            ),
          Text(
            '${question.number}. ${question.text.isEmpty ? 'Listen and choose the best answer.' : question.text}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in question.options.entries)
            if (entry.value.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${entry.key}. ${entry.value}',
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
          const Divider(height: 18, color: AppColors.border),
        ],
      ),
    );
  }
}

String getHighlightKey({
  required String testName,
  required String partFolder,
  required int questionNumber,
  required String qid,
  required String component,
}) {
  return '${testName}_${partFolder}_${questionNumber}_${qid}_$component';
}

class HighlightManager {
  static Map<String, List<TextHighlightMark>> _cache = {};
  static late File _file;

  static Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/highlights.json');
      if (await _file.exists()) {
        final content = await _file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        _cache = json.map((key, value) {
          final list = (value as List)
              .map(
                (item) =>
                    TextHighlightMark.fromJson(item as Map<String, dynamic>),
              )
              .toList();
          return MapEntry(key, list);
        });
      }
    } catch (e) {
      debugPrint('Error loading highlights: $e');
    }
  }

  static Future<void> _save() async {
    try {
      final json = _cache.map((key, value) {
        return MapEntry(key, value.map((m) => m.toJson()).toList());
      });
      await _file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Error saving highlights: $e');
    }
  }

  static List<TextHighlightMark> getHighlights(String key) {
    return _cache[key] ?? [];
  }

  static void setHighlights(String key, List<TextHighlightMark> marks) {
    _cache[key] = marks;
    _save();
  }
}

class VocabularyManager {
  static Future<List<String>> getVocabularyFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final list = dir.listSync();
      final files = list
          .whereType<File>()
          .where((file) => file.path.endsWith('.txt'))
          .map((file) => file.path.split('/').last.split('\\').last)
          .toList();
      if (!files.contains('vocab.txt')) {
        files.insert(0, 'vocab.txt');
      }
      return files;
    } catch (e) {
      debugPrint('Error getting vocab files: $e');
      return ['vocab.txt'];
    }
  }

  static Future<void> addWord({
    required String filename,
    required String word,
    required String meaning,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cleanName = filename.endsWith('.txt') ? filename : '$filename.txt';
      final file = File('${dir.path}/$cleanName');
      final content = '$word:$meaning\n';
      await file.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      debugPrint('Error adding vocabulary: $e');
    }
  }
}

class AddVocabularyDialog extends StatefulWidget {
  final String initialWord;

  const AddVocabularyDialog({super.key, required this.initialWord});

  @override
  State<AddVocabularyDialog> createState() => _AddVocabularyDialogState();
}

class _AddVocabularyDialogState extends State<AddVocabularyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _wordController;
  final _meaningController = TextEditingController();
  final _fileController = TextEditingController(text: 'vocab.txt');
  List<String> _existingFiles = [];

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.initialWord);
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final files = await VocabularyManager.getVocabularyFiles();
    setState(() {
      _existingFiles = files;
      if (_existingFiles.isNotEmpty &&
          !_existingFiles.contains(_fileController.text)) {
        _fileController.text = _existingFiles.first;
      }
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.blue, size: 28),
          SizedBox(width: 8),
          Text(
            'Thêm từ vựng mới',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Từ vựng',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _wordController,
                decoration: InputDecoration(
                  hintText: 'Nhập từ vựng...',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Không được bỏ trống'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Nghĩa của từ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _meaningController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Nhập nghĩa/dịch nghĩa...',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Không được bỏ trống'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Tên file lưu trữ (.txt)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fileController,
                      decoration: InputDecoration(
                        hintText: 'Nhập tên file...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Không được bỏ trống'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_existingFiles.isNotEmpty)
                    DropdownButton<String>(
                      underline: const SizedBox(),
                      icon: const Icon(
                        Icons.arrow_drop_down_circle,
                        color: AppColors.blue,
                      ),
                      items: _existingFiles.map((filename) {
                        return DropdownMenuItem<String>(
                          value: filename,
                          child: Text(filename),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _fileController.text = val;
                          });
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () async {
            if (_formKey.currentState?.validate() ?? false) {
              final word = _wordController.text.trim();
              final meaning = _meaningController.text.trim();
              final filename = _fileController.text.trim();
              await VocabularyManager.addWord(
                filename: filename,
                word: word,
                meaning: meaning,
              );
              if (context.mounted) {
                Navigator.of(context).pop(meaning);
              }
            }
          },
          child: const Text('Thêm từ vựng'),
        ),
      ],
    );
  }
}

class TestHistoryEntry {
  final String testName;
  final DateTime submittedAt;
  final int correctCount;
  final int totalQuestions;
  final String timeSpent;

  TestHistoryEntry({
    required this.testName,
    required this.submittedAt,
    required this.correctCount,
    required this.totalQuestions,
    required this.timeSpent,
  });

  factory TestHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TestHistoryEntry(
      testName: json['testName'] ?? '',
      submittedAt: DateTime.parse(json['submittedAt']),
      correctCount: json['correctCount'] ?? 0,
      totalQuestions: json['totalQuestions'] ?? 0,
      timeSpent: json['timeSpent'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'testName': testName,
      'submittedAt': submittedAt.toIso8601String(),
      'correctCount': correctCount,
      'totalQuestions': totalQuestions,
      'timeSpent': timeSpent,
    };
  }
}

class TestHistoryManager {
  static final List<TestHistoryEntry> _history = [];
  static late File _file;

  static List<TestHistoryEntry> get history => List.unmodifiable(_history);

  static Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/test_history.json');
      if (await _file.exists()) {
        final content = await _file.readAsString();
        final List decoded = jsonDecode(content);
        _history.clear();
        _history.addAll(
          decoded.map(
            (item) => TestHistoryEntry.fromJson(item as Map<String, dynamic>),
          ),
        );
        _history.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      }
    } catch (e) {
      debugPrint('Error loading test history: $e');
    }
  }

  static Future<void> addEntry(TestHistoryEntry entry) async {
    _history.insert(0, entry);
    await _save();
  }

  static Future<void> _save() async {
    try {
      final content = jsonEncode(_history.map((e) => e.toJson()).toList());
      await _file.writeAsString(content);
    } catch (e) {
      debugPrint('Error saving test history: $e');
    }
  }
}

class TestDownloader {
  static const String r2Host =
      'https://pub-144d4e33ea2b46edbe687c89504ed8b8.r2.dev';

  static Future<String> _fetchString(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      } else {
        throw HttpException('Status code: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<void> _downloadFile(String url, String savePath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        await response.pipe(sink);
      } else {
        throw HttpException('Status code: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<void> downloadTest(
    String year,
    String testName, {
    required Function(String status, double progress) onProgress,
  }) async {
    onProgress('Đang chuẩn bị...', 0.0);
    final docDir = await getApplicationDocumentsDirectory();
    final localTestRoot = '${docDir.path}/TOEIC/$year/$testName';

    // 1. Download test_info.json
    onProgress('Tải thông tin bài thi...', 0.05);
    final testInfoUrl =
        '$r2Host/${Uri.encodeComponent(year)}/${Uri.encodeComponent(testName)}/test_info.json';
    String infoRaw = '';
    try {
      infoRaw = await _fetchString(testInfoUrl);
    } catch (e) {
      throw Exception('Không thể tải test_info.json: $e');
    }

    final infoFile = File('$localTestRoot/test_info.json');
    await infoFile.parent.create(recursive: true);
    await infoFile.writeAsString(infoRaw);

    final info = jsonDecode(infoRaw) as Map<String, dynamic>;
    final parts = info['parts'] as Map<String, dynamic>;

    // 2. Prepare the list of files to download
    final downloadTasks = <Map<String, String>>[];

    for (final entry in parts.entries) {
      final partInfo = entry.value as Map<String, dynamic>;
      final partName = partInfo['part_name'] as String;

      final questionsUrl =
          '$r2Host/${Uri.encodeComponent(year)}/${Uri.encodeComponent(testName)}/${Uri.encodeComponent(partName)}/questions.json';
      final questionsPath = '$localTestRoot/$partName/questions.json';
      downloadTasks.add({'url': questionsUrl, 'savePath': questionsPath});
    }

    onProgress('Tải danh sách câu hỏi...', 0.1);
    for (final task in downloadTasks) {
      try {
        await _downloadFile(task['url']!, task['savePath']!);
      } catch (e) {
        debugPrint('Error downloading questions.json: $e');
      }
    }

    final mediaTasks = <Map<String, String>>[];
    for (final entry in parts.entries) {
      final partInfo = entry.value as Map<String, dynamic>;
      final partName = partInfo['part_name'] as String;
      final qPath = '$localTestRoot/$partName/questions.json';
      final qFile = File(qPath);
      if (await qFile.exists()) {
        try {
          final qRaw = await qFile.readAsString();
          final qDecoded = jsonDecode(qRaw) as Map<String, dynamic>;
          final questions = ((qDecoded['questions'] as List?) ?? []);
          for (final q in questions) {
            final qMap = q as Map<String, dynamic>;
            final audioFiles = (qMap['audio_files'] as List?) ?? [];
            for (final audio in audioFiles) {
              final audioStr = audio as String;
              final audioUrl =
                  '$r2Host/${Uri.encodeComponent(year)}/${Uri.encodeComponent(testName)}/${Uri.encodeComponent(partName)}/${Uri.encodeComponent(audioStr)}';
              final audioPath = '$localTestRoot/$partName/$audioStr';
              mediaTasks.add({'url': audioUrl, 'savePath': audioPath});
            }
            final imageFiles = (qMap['image_files'] as List?) ?? [];
            for (final img in imageFiles) {
              final imgStr = img as String;
              final imgUrl =
                  '$r2Host/${Uri.encodeComponent(year)}/${Uri.encodeComponent(testName)}/${Uri.encodeComponent(partName)}/${Uri.encodeComponent(imgStr)}';
              final imgPath = '$localTestRoot/$partName/$imgStr';
              mediaTasks.add({'url': imgUrl, 'savePath': imgPath});
            }
          }
        } catch (e) {
          debugPrint('Error parsing $qPath: $e');
        }
      }
    }

    for (final entry in parts.entries) {
      final partNumStr = entry.key;
      final partInfo = entry.value as Map<String, dynamic>;
      final partName = partInfo['part_name'] as String;
      if (partNumStr == '6' || partNumStr == '7') {
        final rawHtmlUrl =
            '$r2Host/${Uri.encodeComponent(year)}/${Uri.encodeComponent(testName)}/${Uri.encodeComponent(partName)}/raw.html';
        final rawHtmlPath = '$localTestRoot/$partName/raw.html';
        mediaTasks.add({'url': rawHtmlUrl, 'savePath': rawHtmlPath});
      }
    }

    onProgress('Tải hình ảnh và âm thanh (0/${mediaTasks.length})...', 0.15);
    int downloadedCount = 0;
    final totalMedia = mediaTasks.length;
    if (totalMedia > 0) {
      const maxConcurrency = 5;
      int taskIdx = 0;

      Future<void> worker() async {
        while (true) {
          int currentIdx;
          currentIdx = taskIdx++;
          if (currentIdx >= totalMedia) break;

          final task = mediaTasks[currentIdx];
          try {
            await _downloadFile(task['url']!, task['savePath']!);
          } catch (e) {
            debugPrint('Error downloading file: ${task['url']} - $e');
          }
          downloadedCount++;
          final progress = 0.15 + (downloadedCount / totalMedia) * 0.85;
          onProgress(
            'Tải file phương tiện ($downloadedCount/$totalMedia)...',
            progress,
          );
        }
      }

      final workers = List.generate(
        maxConcurrency < totalMedia ? maxConcurrency : totalMedia,
        (_) => worker(),
      );
      await Future.wait(workers);
    }

    onProgress('Hoàn thành!', 1.0);
  }
}

class DownloadProgressDialog extends StatefulWidget {
  final String year;
  final List<String> testNames;

  const DownloadProgressDialog({
    super.key,
    required this.year,
    required this.testNames,
  });

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Đang chuẩn bị...';
  String _currentTestName = '';
  bool _isFinished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      for (int i = 0; i < widget.testNames.length; i++) {
        final testName = widget.testNames[i];
        setState(() {
          _currentTestName = testName;
          _status = 'Đang tải bài thi...';
        });

        await TestDownloader.downloadTest(
          widget.year,
          testName,
          onProgress: (status, progress) {
            setState(() {
              _status = status;
              final baseProgress = i / widget.testNames.length;
              final testWeight = 1.0 / widget.testNames.length;
              _progress = baseProgress + progress * testWeight;
            });
          },
        );
      }
      setState(() {
        _isFinished = true;
        _status = 'Tải xuống hoàn tất!';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(
        _error != null
            ? 'Lỗi tải xuống'
            : (_isFinished ? 'Tải xuống thành công' : 'Đang tải về máy...'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 320,
        child: _error != null
            ? Text(
                'Đã xảy ra lỗi: $_error',
                style: const TextStyle(color: Colors.red),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isFinished) ...[
                    Text(
                      'Bài thi: $_currentTestName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _status,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      actions: [
        if (_isFinished || _error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xong'),
          ),
      ],
    );
  }
}
