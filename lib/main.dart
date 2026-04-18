import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(900, 660),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FocusApp());
}

// ─── Models ───────────────────────────────────────────────────────────────────

class TodoItem {
  final String id;
  String title;
  bool isCompleted;
  String? tagId;
  TodoItem(
      {required this.id,
      required this.title,
      this.isCompleted = false,
      this.tagId});
}

class WorkTag {
  final String id;
  String name;
  Color color;
  WorkTag({required this.id, required this.name, required this.color});
}

class SessionLog {
  final String? tagId;
  final int minutes;
  final DateTime date;
  SessionLog({required this.tagId, required this.minutes, required this.date});
}

// ─── App ─────────────────────────────────────────────────────────────────────

class FocusApp extends StatelessWidget {
  const FocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Sessions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1C1C1C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8724A),
          surface: Color(0xFF252525),
        ),
      ),
      home: const FocusHomePage(),
    );
  }
}

// ─── Focus Home Page ──────────────────────────────────────────────────────────

class FocusHomePage extends StatefulWidget {
  const FocusHomePage({super.key});

  @override
  State<FocusHomePage> createState() => _FocusHomePageState();
}

class _FocusHomePageState extends State<FocusHomePage>
    with SingleTickerProviderStateMixin {
  // Session state
  int _sessionMinutes = 30;
  int _breakMinutes = 5;
  bool _endSessionSound = true;
  bool _endBreakSound = true;
  bool _isPinned = false;
  bool _isRunning = false;
  int _secondsRemaining = 0;
  Timer? _timer;
  int _completedToday = 0;
  int _dailyGoalHours = 8;
  int _streak = 0;
  int _yesterdayMinutes = 0;

  // Tags
  final List<WorkTag> _tags = [
    WorkTag(id: 't1', name: 'Deep Work', color: const Color(0xFFE8724A)),
    WorkTag(id: 't2', name: 'Learning', color: const Color(0xFF4A90E2)),
    WorkTag(id: 't3', name: 'Meetings', color: const Color(0xFF7ED321)),
    WorkTag(id: 't4', name: 'Admin', color: const Color(0xFFF5A623)),
    WorkTag(id: 't5', name: 'Creative', color: const Color(0xFFBD10E0)),
  ];
  String? _activeTagId;

  // Session logs
  final List<SessionLog> _logs = [];

  // Todos
  final List<TodoItem> _todos = [
    TodoItem(id: '1', title: 'Review project proposal', tagId: 't1'),
    TodoItem(id: '2', title: 'Write weekly report', tagId: 't3'),
    TodoItem(id: '3', title: 'Team standup meeting', tagId: 't3'),
  ];
  final TextEditingController _todoController = TextEditingController();
  final TextEditingController _timerEditController = TextEditingController();
  bool _isEditingTimer = false;
  String? _selectedTaskId;

  // Tab
  late TabController _tabController;

  // Time range for chart: 'today' | 'week' | 'month'
  String _chartRange = 'month';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Seed some demo logs
    final now = DateTime.now();
    final rng = Random(7);
    final tagIds = _tags.map((t) => t.id).toList();
    for (int i = 0; i < 40; i++) {
      final day = now.subtract(Duration(days: rng.nextInt(30)));
      _logs.add(SessionLog(
        tagId: tagIds[rng.nextInt(tagIds.length)],
        minutes: (rng.nextInt(6) + 1) * 5,
        date: DateTime(day.year, day.month, day.day),
      ));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _todoController.dispose();
    _timerEditController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _togglePiP(bool enable) async {
    setState(() => _isPinned = enable);
    if (enable) {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setMinimizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setClosable(false);
      await windowManager.setSize(const Size(320, 360));
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setClosable(true);
      await windowManager.setSize(const Size(900, 660));
      await windowManager.center();
    }
  }

  void _startSession() {
    if (_isRunning) {
      _stopSession();
      return;
    }
    setState(() {
      _isRunning = true;
      _secondsRemaining = _sessionMinutes * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _completedToday += _sessionMinutes;
          _isRunning = false;
          _timer?.cancel();
          _logs.add(SessionLog(
            tagId: _activeTagId,
            minutes: _sessionMinutes,
            date: DateTime.now(),
          ));
          _showCompletionDialog();
        }
      });
    });
  }

  void _stopSession() {
    final elapsed = _sessionMinutes - (_secondsRemaining ~/ 60);
    if (elapsed > 0) {
      _logs.add(SessionLog(
        tagId: _activeTagId,
        minutes: elapsed,
        date: DateTime.now(),
      ));
    }
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _secondsRemaining = 0;
    });
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Session Complete! 🎉',
            style: TextStyle(color: Colors.white)),
        content: Text('You completed a $_sessionMinutes minute focus session.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done',
                  style: TextStyle(color: Color(0xFFE8724A)))),
        ],
      ),
    );
  }

  void _handleTimerEdit(String value) {
    int totalMinutes = 0;
    final parts = value.split(':');
    try {
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        totalMinutes = h * 60 + m;
      } else if (parts.length == 1) {
        totalMinutes = int.tryParse(parts[0]) ?? 0;
      }
    } catch (_) {}

    if (totalMinutes > 0 && totalMinutes <= 1440) {
      setState(() {
        _sessionMinutes = totalMinutes;
        _isEditingTimer = false;
      });
    } else {
      setState(() {
        _isEditingTimer = false;
      });
    }
  }

  void _toggleTimerEdit() {
    if (_isRunning) return;
    final h = _sessionMinutes ~/ 60;
    final m = _sessionMinutes % 60;
    setState(() {
      _isEditingTimer = true;
      _timerEditController.text =
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    });
  }

  String get _timeDisplay {
    if (!_isRunning) {
      final h = _sessionMinutes ~/ 60;
      final m = _sessionMinutes % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final totalSeconds = _secondsRemaining;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _hasBreak => _breakMinutes > 0;

  void _addTodo() {
    final text = _todoController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _todos.add(TodoItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: text,
        tagId: _activeTagId,
      ));
    });
    _todoController.clear();
  }

  void _toggleTodo(String id) {
    setState(() {
      _todos.firstWhere((t) => t.id == id).isCompleted ^= true;
    });
  }

  void _deleteTodo(String id) {
    setState(() {
      _todos.removeWhere((t) => t.id == id);
      if (_selectedTaskId == id) _selectedTaskId = null;
    });
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: _SettingsSheet(
          sessionMinutes: _sessionMinutes,
          breakMinutes: _breakMinutes,
          endSessionSound: _endSessionSound,
          endBreakSound: _endBreakSound,
          onSave: (session, brk, sessSound, brkSound) {
            setState(() {
              _sessionMinutes = session;
              _breakMinutes = brk;
              _endSessionSound = sessSound;
              _endBreakSound = brkSound;
            });
          },
        ),
      ),
    );
  }

  double get _progressFraction {
    final goalMinutes = _dailyGoalHours * 60;
    if (goalMinutes == 0) return 0;
    return (_completedToday / goalMinutes).clamp(0.0, 1.0);
  }

  WorkTag? _tagById(String? id) => id == null
      ? null
      : _tags.firstWhere((t) => t.id == id, orElse: () => _tags.first);

  // ── Chart data helpers ────────────────────────────────────────────────────

  List<SessionLog> get _filteredLogs {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _logs.where((l) {
      final d = DateTime(l.date.year, l.date.month, l.date.day);
      if (_chartRange == 'today') return d == today;
      if (_chartRange == 'week')
        return d.isAfter(today.subtract(const Duration(days: 7)));
      // month
      return d.isAfter(today.subtract(const Duration(days: 30)));
    }).toList();
  }

  Map<String?, int> get _tagMinutes {
    final map = <String?, int>{};
    for (final log in _filteredLogs) {
      map[log.tagId] = (map[log.tagId] ?? 0) + log.minutes;
    }
    return map;
  }

  int get _totalFilteredMinutes =>
      _filteredLogs.fold(0, (sum, l) => sum + l.minutes);

  String _fmtDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _fmtDurationLong(int minutes) {
    final d = minutes ~/ 1440;
    final h = (minutes % 1440) ~/ 60;
    final m = minutes % 60;
    final parts = <String>[];
    if (d > 0) parts.add('${d}d');
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    return parts.isEmpty ? '0m' : parts.join(' ');
  }

  List<MapEntry<String?, int>> get _todaySortedEntries {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayLogs = _logs.where((l) {
      final d = DateTime(l.date.year, l.date.month, l.date.day);
      return d == today;
    }).toList();

    final map = <String?, int>{};
    for (final log in todayLogs) {
      map[log.tagId] = (map[log.tagId] ?? 0) + log.minutes;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isPinned) {
      return _PipOverlay(
        sessionMinutes: _sessionMinutes,
        breakMinutes: _breakMinutes,
        isRunning: _isRunning,
        timeDisplay: _timeDisplay,
        hasBreak: _hasBreak,
        onIncrement: _isRunning
            ? null
            : () => setState(() {
                  if (_sessionMinutes < 240) _sessionMinutes += 5;
                }),
        onDecrement: _isRunning
            ? null
            : () => setState(() {
                  if (_sessionMinutes > 5) _sessionMinutes -= 5;
                }),
        onStart: _startSession,
        onClose: () => _togglePiP(false),
        isEditing: _isEditingTimer,
        timerController: _timerEditController,
        onTimerTapped: _toggleTimerEdit,
        onTimerSubmitted: _handleTimerEdit,
      );
    }

    final w = MediaQuery.of(context).size.width;
    final isWide = w > 720;

    return Scaffold(
      body: Container(
        color: const Color(0xFF1A1A1A),
        child: Column(
          children: [
            // ── Tab Bar ──
            Container(
              color: const Color(0xFF1E1E1E),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFE8724A),
                indicatorWeight: 2,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Focus'),
                  Tab(text: 'Work Tracking'),
                ],
              ),
            ),

            // ── Tab Views ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Tab 1: Focus ──
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    _FocusCard(
                                      sessionMinutes: _sessionMinutes,
                                      isRunning: _isRunning,
                                      timeDisplay: _timeDisplay,
                                      hasBreak: _hasBreak,
                                      isPinned: _isPinned,
                                      activeTag: _tagById(_activeTagId),
                                      tags: _tags,
                                      onTagSelected: (id) =>
                                          setState(() => _activeTagId = id),
                                      onIncrement: _isRunning
                                          ? null
                                          : () => setState(() {
                                                if (_sessionMinutes < 240)
                                                  _sessionMinutes += 5;
                                              }),
                                      onDecrement: _isRunning
                                          ? null
                                          : () => setState(() {
                                                if (_sessionMinutes > 5)
                                                  _sessionMinutes -= 5;
                                              }),
                                      onStart: _startSession,
                                      onTogglePin: () => _togglePiP(true),
                                      onOpenSettings: () =>
                                          _showSettingsSheet(context),
                                      isEditing: _isEditingTimer,
                                      timerController: _timerEditController,
                                      onTimerTapped: _toggleTimerEdit,
                                      onTimerSubmitted: _handleTimerEdit,
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                        child: _TodoCard(
                                      todos: _todos,
                                      tags: _tags,
                                      controller: _todoController,
                                      selectedTaskId: _selectedTaskId,
                                      onAdd: _addTodo,
                                      onToggle: _toggleTodo,
                                      onDelete: _deleteTodo,
                                      onSelect: (id) =>
                                          setState(() => _selectedTaskId = id),
                                    )),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 300,
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _DailyProgressCard(
                                        yesterdayMinutes: _yesterdayMinutes,
                                        dailyGoalHours: _dailyGoalHours,
                                        streak: _streak,
                                        completedMinutes: _completedToday,
                                        progressFraction: _progressFraction,
                                        onGoalChanged: (h) => setState(
                                            () => _dailyGoalHours = h),
                                      ),
                                      const SizedBox(height: 16),
                                      _TagRankingCard(
                                        sorted: _todaySortedEntries,
                                        tags: _tags,
                                        totalMinutes: _completedToday,
                                        fmtDuration: _fmtDuration,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(children: [
                              _FocusCard(
                                sessionMinutes: _sessionMinutes,
                                isRunning: _isRunning,
                                timeDisplay: _timeDisplay,
                                hasBreak: _hasBreak,
                                isPinned: _isPinned,
                                activeTag: _tagById(_activeTagId),
                                tags: _tags,
                                onTagSelected: (id) =>
                                    setState(() => _activeTagId = id),
                                onIncrement: _isRunning
                                    ? null
                                    : () => setState(() {
                                          if (_sessionMinutes < 240)
                                            _sessionMinutes += 5;
                                        }),
                                onDecrement: _isRunning
                                    ? null
                                    : () => setState(() {
                                          if (_sessionMinutes > 5)
                                            _sessionMinutes -= 5;
                                        }),
                                onStart: _startSession,
                                onTogglePin: () => _togglePiP(true),
                                onOpenSettings: () =>
                                    _showSettingsSheet(context),
                                isEditing: _isEditingTimer,
                                timerController: _timerEditController,
                                onTimerTapped: _toggleTimerEdit,
                                onTimerSubmitted: _handleTimerEdit,
                              ),
                              const SizedBox(height: 16),
                              _DailyProgressCard(
                                yesterdayMinutes: _yesterdayMinutes,
                                dailyGoalHours: _dailyGoalHours,
                                streak: _streak,
                                completedMinutes: _completedToday,
                                progressFraction: _progressFraction,
                                onGoalChanged: (h) =>
                                    setState(() => _dailyGoalHours = h),
                              ),
                              const SizedBox(height: 16),
                              _TagRankingCard(
                                sorted: _todaySortedEntries,
                                tags: _tags,
                                totalMinutes: _completedToday,
                                fmtDuration: _fmtDuration,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                  height: 380,
                                  child: _TodoCard(
                                    todos: _todos,
                                    tags: _tags,
                                    controller: _todoController,
                                    selectedTaskId: _selectedTaskId,
                                    onAdd: _addTodo,
                                    onToggle: _toggleTodo,
                                    onDelete: _deleteTodo,
                                    onSelect: (id) =>
                                        setState(() => _selectedTaskId = id),
                                  )),
                            ]),
                          ),
                  ),

                  // ── Tab 2: Work Tracking ──
                  _WorkTrackingTab(
                    tags: _tags,
                    tagMinutes: _tagMinutes,
                    totalMinutes: _totalFilteredMinutes,
                    chartRange: _chartRange,
                    filteredLogs: _filteredLogs,
                    onRangeChanged: (r) => setState(() => _chartRange = r),
                    fmtDuration: _fmtDuration,
                    fmtDurationLong: _fmtDurationLong,
                    onAddTag: () => _showAddTagDialog(context),
                    onEditTag: (tag) => _showEditTagDialog(context, tag),
                    onDeleteTag: (id) => setState(() {
                      _tags.removeWhere((t) => t.id == id);
                      if (_activeTagId == id) _activeTagId = null;
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTagDialog(BuildContext context) {
    final ctrl = TextEditingController();
    Color picked = const Color(0xFFE8724A);
    final colors = [
      const Color(0xFFE8724A),
      const Color(0xFF4A90E2),
      const Color(0xFF7ED321),
      const Color(0xFFF5A623),
      const Color(0xFFBD10E0),
      const Color(0xFF50E3C2),
      const Color(0xFFE91E8C),
      const Color(0xFF00BCD4),
      const Color(0xFF8BC34A),
    ];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: const Text('New Tag',
                    style: TextStyle(color: Colors.white)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: ctrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Tag name',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE8724A))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors
                          .map((c) => GestureDetector(
                                onTap: () => setS(() => picked = c),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: picked == c
                                        ? Border.all(
                                            color: Colors.white, width: 2)
                                        : null,
                                  ),
                                ),
                              ))
                          .toList()),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white54))),
                  TextButton(
                    onPressed: () {
                      if (ctrl.text.trim().isNotEmpty) {
                        setState(() => _tags.add(WorkTag(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              name: ctrl.text.trim(),
                              color: picked,
                            )));
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Add',
                        style: TextStyle(color: Color(0xFFE8724A))),
                  ),
                ],
              )),
    );
  }

  void _showEditTagDialog(BuildContext context, WorkTag tag) {
    final ctrl = TextEditingController(text: tag.name);
    Color picked = tag.color;
    final colors = [
      const Color(0xFFE8724A),
      const Color(0xFF4A90E2),
      const Color(0xFF7ED321),
      const Color(0xFFF5A623),
      const Color(0xFFBD10E0),
      const Color(0xFF50E3C2),
      const Color(0xFFE91E8C),
      const Color(0xFF00BCD4),
      const Color(0xFF8BC34A),
    ];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: const Text('Edit Tag',
                    style: TextStyle(color: Colors.white)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: ctrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Tag name',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE8724A))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors
                          .map((c) => GestureDetector(
                                onTap: () => setS(() => picked = c),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: picked == c
                                        ? Border.all(
                                            color: Colors.white, width: 2)
                                        : null,
                                  ),
                                ),
                              ))
                          .toList()),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white54))),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        tag.name = ctrl.text.trim().isEmpty
                            ? tag.name
                            : ctrl.text.trim();
                        tag.color = picked;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save',
                        style: TextStyle(color: Color(0xFFE8724A))),
                  ),
                ],
              )),
    );
  }
}

// ─── Work Tracking Tab ────────────────────────────────────────────────────────

class _WorkTrackingTab extends StatefulWidget {
  final List<WorkTag> tags;
  final Map<String?, int> tagMinutes;
  final int totalMinutes;
  final String chartRange;
  final List<SessionLog> filteredLogs;
  final ValueChanged<String> onRangeChanged;
  final String Function(int) fmtDuration;
  final String Function(int) fmtDurationLong;
  final VoidCallback onAddTag;
  final ValueChanged<WorkTag> onEditTag;
  final ValueChanged<String> onDeleteTag;

  const _WorkTrackingTab({
    required this.tags,
    required this.tagMinutes,
    required this.totalMinutes,
    required this.chartRange,
    required this.filteredLogs,
    required this.onRangeChanged,
    required this.fmtDuration,
    required this.fmtDurationLong,
    required this.onAddTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  @override
  State<_WorkTrackingTab> createState() => _WorkTrackingTabState();
}

class _WorkTrackingTabState extends State<_WorkTrackingTab> {
  int? _hoveredIndex;
  bool _showRanking = false;

  String _rangeLabel() {
    final now = DateTime.now();
    final fmt = (DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    if (widget.chartRange == 'today') return fmt(now);
    if (widget.chartRange == 'week')
      return '${fmt(now.subtract(const Duration(days: 7)))} - ${fmt(now)}';
    return '${fmt(now.subtract(const Duration(days: 30)))} - ${fmt(now)}';
  }

  String _avgPerDay() {
    final days = widget.chartRange == 'today'
        ? 1
        : widget.chartRange == 'week'
            ? 7
            : 30;
    final avg = widget.totalMinutes ~/ days;
    return widget.fmtDuration(avg) + ' per day on average';
  }

  List<MapEntry<String?, int>> get _sortedEntries {
    final entries = widget.tagMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  WorkTag? _tagById(String? id) => id == null
      ? null
      : widget.tags.firstWhere((t) => t.id == id,
          orElse: () => WorkTag(id: '', name: 'Untagged', color: Colors.grey));

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedEntries;
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 1000;

    final rangeLabel = _chartRange_label(widget.chartRange);

    final chartArea = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Chart header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Legend (left)
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sorted.take(10).map((e) {
                      final tag = _tagById(e.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: tag?.color ?? Colors.grey,
                                  borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(tag?.name ?? 'Untagged',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12))),
                        ]),
                      );
                    }).toList(),
                  ),
                ),

                // Center: title + pie chart
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _chartTitle(widget.chartRange),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total ${widget.fmtDurationLong(widget.totalMinutes)}  ${_rangeLabel()}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                      Text(_avgPerDay(),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      const SizedBox(height: 12),
                      // Pie
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: _PieChart(
                          entries: sorted,
                          tags: widget.tags,
                          totalMinutes: widget.totalMinutes,
                          hoveredIndex: _hoveredIndex,
                          fmtDuration: widget.fmtDuration,
                          onHover: (i) => setState(() => _hoveredIndex = i),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom bar: tabs + range selector ──
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Distribution / Ranking toggle
                  _TabToggle(
                    labels: const ['Distribution', 'Ranking'],
                    selected: _showRanking ? 1 : 0,
                    onSelect: (i) => setState(() => _showRanking = i == 1),
                  ),
                  // Range picker
                  _RangeDropdown(
                    value: widget.chartRange,
                    onChanged: widget.onRangeChanged,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final tagListArea = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _showRanking
          ? _RankingView(
              sorted: sorted,
              tags: widget.tags,
              totalMinutes: widget.totalMinutes,
              fmtDuration: widget.fmtDuration,
              onEdit: widget.onEditTag,
              onDelete: widget.onDeleteTag,
            )
          : _TagManageView(
              tags: widget.tags,
              tagMinutes: widget.tagMinutes,
              fmtDuration: widget.fmtDuration,
              onEdit: widget.onEditTag,
              onDelete: widget.onDeleteTag,
            ),
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Top bar ──
          Row(
            children: [
              const Text('Work Tracking',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              // Add tag button
              GestureDetector(
                onTap: widget.onAddTag,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.add, color: Colors.white54, size: 14),
                    SizedBox(width: 4),
                    Text('New Tag',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isWide)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: chartArea),
                  const SizedBox(width: 16),
                  Expanded(child: tagListArea),
                ],
              ),
            )
          else ...[
            chartArea,
            const SizedBox(height: 16),
            Expanded(child: tagListArea),
          ],
        ],
      ),
    );
  }

  String _chartTitle(String range) {
    if (range == 'today') return "Today's Data";
    if (range == 'week') return "This Week's Data";
    return "This Month's Data";
  }

  String _chartRange_label(String range) => range;
}

// ─── Pie Chart ────────────────────────────────────────────────────────────────

class _PieChart extends StatelessWidget {
  final List<MapEntry<String?, int>> entries;
  final List<WorkTag> tags;
  final int totalMinutes;
  final int? hoveredIndex;
  final String Function(int) fmtDuration;
  final ValueChanged<int?> onHover;

  const _PieChart({
    required this.entries,
    required this.tags,
    required this.totalMinutes,
    required this.hoveredIndex,
    required this.fmtDuration,
    required this.onHover,
  });

  WorkTag? _tagById(String? id) => id == null
      ? null
      : tags.firstWhere((t) => t.id == id,
          orElse: () => WorkTag(id: '', name: 'Untagged', color: Colors.grey));

  @override
  Widget build(BuildContext context) {
    if (totalMinutes == 0) {
      return const Center(
        child: Text('No sessions recorded yet.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    return MouseRegion(
      child: CustomPaint(
        painter: _PieChartPainter(
          entries: entries,
          tags: tags,
          totalMinutes: totalMinutes,
          hoveredIndex: hoveredIndex,
          fmtDuration: fmtDuration,
        ),
        child: GestureDetector(
          onTapUp: (details) {
            // tap handling via painter hit-test
          },
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<MapEntry<String?, int>> entries;
  final List<WorkTag> tags;
  final int totalMinutes;
  final int? hoveredIndex;
  final String Function(int) fmtDuration;

  _PieChartPainter({
    required this.entries,
    required this.tags,
    required this.totalMinutes,
    required this.hoveredIndex,
    required this.fmtDuration,
  });

  WorkTag? _tagById(String? id) => id == null
      ? null
      : tags.firstWhere((t) => t.id == id,
          orElse: () => WorkTag(id: '', name: 'Untagged', color: Colors.grey));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;

    double startAngle = -pi / 2;
    final total = totalMinutes.toDouble();

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final sweep = (e.value / total) * 2 * pi;
      final isHovered = hoveredIndex == i;
      final tag = _tagById(e.key);
      final color = tag?.color ?? Colors.grey;

      final r = isHovered ? radius + 6 : radius;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: r), startAngle, sweep,
            false)
        ..close();

      canvas.drawPath(path, paint);

      // Gap between slices
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF252525)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // Label line for larger slices
      if (sweep > 0.25) {
        final midAngle = startAngle + sweep / 2;
        final labelR = r * 0.75;
        final lx = center.dx + cos(midAngle) * labelR;
        final ly = center.dy + sin(midAngle) * labelR;

        final tp = TextPainter(
          text: TextSpan(
            text: tag?.name ?? 'Untagged',
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
      }

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.hoveredIndex != hoveredIndex || old.totalMinutes != totalMinutes;
}

// ─── Tab Toggle ───────────────────────────────────────────────────────────────

class _TabToggle extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const _TabToggle(
      {required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          labels.length,
          (i) => GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? const Color(0xFFE8724A)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.horizontal(
                      left: i == 0 ? const Radius.circular(8) : Radius.zero,
                      right: i == labels.length - 1
                          ? const Radius.circular(8)
                          : Radius.zero,
                    ),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                        color: selected == i ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight:
                            selected == i ? FontWeight.w600 : FontWeight.normal,
                      )),
                ),
              )),
    );
  }
}

// ─── Range Dropdown ───────────────────────────────────────────────────────────

class _RangeDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _RangeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButton<String>(
        value: value,
        items: const [
          DropdownMenuItem(
              value: 'today',
              child: Text('Today',
                  style: TextStyle(color: Colors.white, fontSize: 12))),
          DropdownMenuItem(
              value: 'week',
              child: Text('This week',
                  style: TextStyle(color: Colors.white, fontSize: 12))),
          DropdownMenuItem(
              value: 'month',
              child: Text('This month',
                  style: TextStyle(color: Colors.white, fontSize: 12))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        dropdownColor: const Color(0xFF2A2A2A),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: Colors.white38, size: 14),
        isDense: true,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

// ─── Ranking View ─────────────────────────────────────────────────────────────

class _RankingView extends StatelessWidget {
  final List<MapEntry<String?, int>> sorted;
  final List<WorkTag> tags;
  final int totalMinutes;
  final String Function(int) fmtDuration;
  final ValueChanged<WorkTag> onEdit;
  final ValueChanged<String> onDelete;

  const _RankingView({
    required this.sorted,
    required this.tags,
    required this.totalMinutes,
    required this.fmtDuration,
    required this.onEdit,
    required this.onDelete,
  });

  WorkTag? _tagById(String? id) => id == null
      ? null
      : tags.firstWhere((t) => t.id == id,
          orElse: () => WorkTag(id: '', name: 'Untagged', color: Colors.grey));

  @override
  Widget build(BuildContext context) {
    if (sorted.isEmpty) {
      return const Center(
          child: Text('No data yet.', style: TextStyle(color: Colors.white38)));
    }
    final maxVal = sorted.first.value.toDouble();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final e = sorted[i];
        final tag = _tagById(e.key);
        final frac = maxVal > 0 ? e.value / maxVal : 0.0;
        final pct =
            totalMinutes > 0 ? (e.value / totalMinutes * 100).round() : 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(
                width: 20,
                child: Text('${i + 1}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11))),
            const SizedBox(width: 8),
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: tag?.color ?? Colors.grey,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            SizedBox(
                width: 90,
                child: Text(tag?.name ?? 'Untagged',
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(
              child: Stack(children: [
                Container(
                    height: 18,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4))),
                FractionallySizedBox(
                  widthFactor: frac.clamp(0.0, 1.0),
                  child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                          color: (tag?.color ?? Colors.grey).withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4))),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 40,
                child: Text(fmtDuration(e.value),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11))),
            SizedBox(
                width: 34,
                child: Text('$pct%',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        );
      },
    );
  }
}

// ─── Tag Manage View ─────────────────────────────────────────────────────────

class _TagManageView extends StatelessWidget {
  final List<WorkTag> tags;
  final Map<String?, int> tagMinutes;
  final String Function(int) fmtDuration;
  final ValueChanged<WorkTag> onEdit;
  final ValueChanged<String> onDelete;

  const _TagManageView({
    required this.tags,
    required this.tagMinutes,
    required this.fmtDuration,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tags.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white10, height: 1),
      itemBuilder: (ctx, i) {
        final tag = tags[i];
        final mins = tagMinutes[tag.id] ?? 0;
        return ListTile(
          dense: true,
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: tag.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          title: Text(tag.name,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          subtitle: Text(mins > 0 ? fmtDuration(mins) : 'No sessions',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 16, color: Colors.white38),
              onPressed: () => onEdit(tag),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Colors.white24),
              onPressed: () => onDelete(tag.id),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        );
      },
    );
  }
}

// ─── PiP Overlay ─────────────────────────────────────────────────────────────

class _PipOverlay extends StatelessWidget {
  final int sessionMinutes, breakMinutes;
  final bool isRunning, hasBreak;
  final String timeDisplay;
  final VoidCallback? onIncrement, onDecrement;
  final VoidCallback onStart, onClose;
  final bool isEditing;
  final TextEditingController timerController;
  final VoidCallback onTimerTapped;
  final ValueChanged<String> onTimerSubmitted;

  const _PipOverlay({
    required this.sessionMinutes,
    required this.breakMinutes,
    required this.isRunning,
    required this.hasBreak,
    required this.timeDisplay,
    required this.onIncrement,
    required this.onDecrement,
    required this.onStart,
    required this.onClose,
    required this.isEditing,
    required this.timerController,
    required this.onTimerTapped,
    required this.onTimerSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF212121),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.open_in_full,
                        size: 14, color: Colors.white24),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message:
                          isRunning ? 'Timer running' : 'Click to edit duration',
                      child: GestureDetector(
                        onTap: isRunning ? null : onTimerTapped,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: isEditing
                              ? SizedBox(
                                  width: 150,
                                  child: TextField(
                                    controller: timerController,
                                    autofocus: true,
                                    keyboardType: TextInputType.datetime,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w200,
                                        fontFamily: 'monospace'),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                      hintText: '00:00',
                                      hintStyle: TextStyle(color: Colors.white12),
                                    ),
                                    onSubmitted: onTimerSubmitted,
                                  ),
                                )
                              : Text(timeDisplay,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w200,
                                      fontFamily: 'monospace')),
                        ),
                      ),
                    ),
                    if (!isRunning && !isEditing) ...[
                      const SizedBox(width: 8),
                      Column(children: [
                        _ArrowButton(
                            icon: Icons.keyboard_arrow_up, onTap: onIncrement),
                        const SizedBox(height: 4),
                        _ArrowButton(
                            icon: Icons.keyboard_arrow_down,
                            onTap: onDecrement),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasBreak
                    ? 'Session includes a $breakMinutes min break'
                    : 'No breaks',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8724A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Icon(isRunning ? Icons.stop : Icons.play_arrow,
                        size: 20),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Focus Card ───────────────────────────────────────────────────────────────

class _FocusCard extends StatelessWidget {
  final int sessionMinutes;
  final bool isRunning, hasBreak, isPinned;
  final String timeDisplay;
  final WorkTag? activeTag;
  final List<WorkTag> tags;
  final ValueChanged<String?> onTagSelected;
  final VoidCallback? onIncrement, onDecrement;
  final VoidCallback onStart, onTogglePin, onOpenSettings;
  final bool isEditing;
  final TextEditingController timerController;
  final VoidCallback onTimerTapped;
  final ValueChanged<String> onTimerSubmitted;

  const _FocusCard({
    required this.sessionMinutes,
    required this.isRunning,
    required this.timeDisplay,
    required this.hasBreak,
    required this.isPinned,
    required this.activeTag,
    required this.tags,
    required this.onTagSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onStart,
    required this.onTogglePin,
    required this.onOpenSettings,
    required this.isEditing,
    required this.timerController,
    required this.onTimerTapped,
    required this.onTimerSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Get ready to focus',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Tooltip(
                    message: 'Compact view',
                    child: GestureDetector(
                      onTap: onTogglePin,
                      child: const Icon(Icons.picture_in_picture_alt,
                          color: Colors.white38, size: 17),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Settings',
                    child: GestureDetector(
                      onTap: onOpenSettings,
                      child: const Icon(Icons.more_horiz,
                          color: Colors.white38, size: 20),
                    ),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 16),

              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  // Timer
                  Tooltip(
                    message: isRunning ? 'Timer running' : 'Click to edit duration',
                    child: GestureDetector(
                      onTap: isRunning ? null : onTimerTapped,
                      child: Container(
                        decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: isEditing
                            ? SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: timerController,
                                  autofocus: true,
                                  keyboardType: TextInputType.datetime,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w300,
                                      fontFamily: 'monospace'),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    hintText: '00:00',
                                    hintStyle: TextStyle(color: Colors.white12),
                                  ),
                                  onSubmitted: onTimerSubmitted,
                                ),
                              )
                            : Text(timeDisplay,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w300,
                                    fontFamily: 'monospace')),
                      ),
                    ),
                  ),
                  if (!isRunning && !isEditing) ...[
                    Column(children: [
                      _ArrowButton(
                          icon: Icons.keyboard_arrow_up, onTap: onIncrement),
                      const SizedBox(height: 4),
                      _ArrowButton(
                          icon: Icons.keyboard_arrow_down, onTap: onDecrement),
                    ]),
                  ],

                  // Tag selector
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Tag this session',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          // None chip
                          _TagChip(
                            label: 'None',
                            color: Colors.white24,
                            selected: activeTag == null,
                            onTap: () => onTagSelected(null),
                          ),
                          ...tags.map((t) => _TagChip(
                                label: t.name,
                                color: t.color,
                                selected: activeTag?.id == t.id,
                                onTap: () => onTagSelected(t.id),
                              )),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

            const SizedBox(height: 12),
            Text(
                hasBreak
                    ? 'Session includes a short break'
                    : "You'll have no breaks",
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStart,
                icon:
                    Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 17),
                label: Text(isRunning ? 'Stop session' : 'Start focus session',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8724A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.25) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? color : Colors.white38,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                )),
          ),
        ]),
      ),
    );
  }
}// ─── Arrow Button ─────────────────────────────────────────────────────────────

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ArrowButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(6)),
        child: Icon(icon,
            color: onTap != null ? Colors.white70 : Colors.white24, size: 16),
      ),
    );
  }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final int sessionMinutes, breakMinutes;
  final bool endSessionSound, endBreakSound;
  final void Function(int, int, bool, bool) onSave;

  const _SettingsSheet({
    required this.sessionMinutes,
    required this.breakMinutes,
    required this.endSessionSound,
    required this.endBreakSound,
    required this.onSave,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _session, _brk;
  late bool _sessSound, _brkSound;
  bool _periodsExpanded = true;

  static const _sessionOptions = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120];
  static const _breakOptions = [5, 10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    _session = widget.sessionMinutes;
    _brk = widget.breakMinutes;
    _sessSound = widget.endSessionSound;
    _brkSound = widget.endBreakSound;
  }

  void _save() => widget.onSave(_session, _brk, _sessSound, _brkSound);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(children: [
                const Text('Settings',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    _save();
                    Navigator.pop(context);
                  },
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Focus sessions',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5))),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.timer_outlined,
              title: 'Focus periods',
              subtitle:
                  'Adjust the lengths of your focus time, or breaks to fit your needs.',
              trailing: IconButton(
                onPressed: () =>
                    setState(() => _periodsExpanded = !_periodsExpanded),
                icon: Icon(
                    _periodsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 20),
              ),
            ),
            if (_periodsExpanded) ...[
              _SettingsSubRow(
                  label: 'Focus period',
                  child: _DropdownPicker(
                    value: _session,
                    options: _sessionOptions,
                    label: (v) => '$v minutes',
                    onChanged: (v) {
                      setState(() => _session = v);
                      _save();
                    },
                  )),
              _SettingsSubRow(
                  label: 'Break period',
                  child: _DropdownPicker(
                    value: _brk,
                    options: _breakOptions,
                    label: (v) => '$v minutes',
                    onChanged: (v) {
                      setState(() => _brk = v);
                      _save();
                    },
                  )),
            ],
            _SettingsTile(
              icon: Icons.alarm_outlined,
              title: 'End of session sound',
              subtitle: 'Play an alarm when focus period ends',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_sessSound ? 'On' : 'Off',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 8),
                Switch(
                    value: _sessSound,
                    onChanged: (v) {
                      setState(() => _sessSound = v);
                      _save();
                    },
                    activeThumbColor: const Color(0xFFE8724A),
                    activeTrackColor: const Color(0xFFE8724A).withOpacity(0.4),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: Colors.white12),
              ]),
            ),
            _SettingsTile(
              icon: Icons.alarm_outlined,
              title: 'End of break sound',
              subtitle: 'Play an alarm when breaks end',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_brkSound ? 'On' : 'Off',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 8),
                Switch(
                    value: _brkSound,
                    onChanged: (v) {
                      setState(() => _brkSound = v);
                      _save();
                    },
                    activeThumbColor: const Color(0xFFE8724A),
                    activeTrackColor: const Color(0xFFE8724A).withOpacity(0.4),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: Colors.white12),
              ]),
            ),
            const SizedBox(height: 16),
          ]),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget trailing;
  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: Colors.white54, size: 22),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ])),
        trailing,
      ]),
    );
  }
}

class _SettingsSubRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingsSubRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(children: [
        const SizedBox(width: 36),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13))),
        child,
      ]),
    );
  }
}

class _DropdownPicker extends StatelessWidget {
  final int value;
  final List<int> options;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  const _DropdownPicker(
      {required this.value,
      required this.options,
      required this.label,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(8)),
      child: DropdownButton<int>(
        value: options.contains(value) ? value : options.first,
        items: options
            .map((v) => DropdownMenuItem(
                value: v,
                child: Text(label(v),
                    style: const TextStyle(color: Colors.white, fontSize: 13))))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        dropdownColor: const Color(0xFF333333),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: Colors.white54, size: 16),
        isDense: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

// ─── Daily Progress Card ──────────────────────────────────────────────────────

class _DailyProgressCard extends StatelessWidget {
  final int yesterdayMinutes, dailyGoalHours, streak, completedMinutes;
  final double progressFraction;
  final ValueChanged<int> onGoalChanged;

  const _DailyProgressCard({
    required this.yesterdayMinutes,
    required this.dailyGoalHours,
    required this.streak,
    required this.completedMinutes,
    required this.progressFraction,
    required this.onGoalChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Daily progress',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          GestureDetector(
            onTap: () => _showGoalDialog(context),
            child: const Icon(Icons.edit_outlined,
                color: Colors.white38, size: 16),
          ),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _StatColumn(
              label: 'Yesterday',
              value: yesterdayMinutes.toString(),
              unit: 'mins'),
          _ProgressRing(
              fraction: progressFraction,
              centerLabel: dailyGoalHours.toString(),
              centerSub: 'hours',
              topLabel: 'Daily goal'),
          _StatColumn(label: 'Streak', value: streak.toString(), unit: 'days'),
        ]),
        const SizedBox(height: 16),
        Center(
            child: Text('Completed: $completedMinutes min',
                style: const TextStyle(color: Colors.white38, fontSize: 12))),
      ]),
    );
  }

  void _showGoalDialog(BuildContext context) {
    int tempGoal = dailyGoalHours;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: const Text('Set Daily Goal',
                    style: TextStyle(color: Colors.white)),
                content:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      onPressed: () => setS(() {
                            if (tempGoal > 1) tempGoal--;
                          }),
                      icon: const Icon(Icons.remove, color: Colors.white70)),
                  Text('$tempGoal hrs',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 22)),
                  IconButton(
                      onPressed: () => setS(() {
                            if (tempGoal < 16) tempGoal++;
                          }),
                      icon: const Icon(Icons.add, color: Colors.white70)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white54))),
                  TextButton(
                      onPressed: () {
                        onGoalChanged(tempGoal);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Save',
                          style: TextStyle(color: Color(0xFFE8724A)))),
                ],
              )),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label, value, unit;
  const _StatColumn(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300)),
      Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }
}

class _ProgressRing extends StatelessWidget {
  final double fraction;
  final String centerLabel, centerSub, topLabel;

  const _ProgressRing(
      {required this.fraction,
      required this.centerLabel,
      required this.centerSub,
      required this.topLabel});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(topLabel,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 6),
      SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                  size: const Size(90, 90),
                  painter: _RingPainter(fraction: fraction)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(centerLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300)),
                Text(centerSub,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ],
          )),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  const _RingPainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF3A3A3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round);
    if (fraction > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -pi / 2,
          fraction * 2 * pi,
          false,
          Paint()
            ..color = const Color(0xFFE8724A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

// ─── Todo Card ────────────────────────────────────────────────────────────────

class _TodoCard extends StatelessWidget {
  final List<TodoItem> todos;
  final List<WorkTag> tags;
  final TextEditingController controller;
  final String? selectedTaskId;
  final VoidCallback onAdd;
  final ValueChanged<String> onToggle, onDelete;
  final ValueChanged<String?> onSelect;

  const _TodoCard({
    required this.todos,
    required this.tags,
    required this.controller,
    required this.selectedTaskId,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onSelect,
  });

  WorkTag? _tagById(String? id) => id == null
      ? null
      : tags.firstWhere((t) => t.id == id, orElse: () => tags.first);

  @override
  Widget build(BuildContext context) {
    final pending = todos.where((t) => !t.isCompleted).toList();
    final done = todos.where((t) => t.isCompleted).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  color: const Color(0xFF2564CF),
                  borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.check, color: Colors.white, size: 12)),
          const SizedBox(width: 8),
          const Text('To Do',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${pending.length} remaining',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add a task...',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon:
                  const Icon(Icons.add, color: Colors.white24, size: 16),
            ),
            onSubmitted: (_) => onAdd(),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFE8724A),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(
            child: ListView(children: [
          ...pending.map((t) => _TodoTile(
                item: t,
                tag: _tagById(t.tagId),
                isSelected: selectedTaskId == t.id,
                onToggle: () => onToggle(t.id),
                onDelete: () => onDelete(t.id),
                onSelect: () => onSelect(selectedTaskId == t.id ? null : t.id),
              )),
          if (done.isNotEmpty) ...[
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Completed',
                    style: TextStyle(color: Colors.white24, fontSize: 11))),
            ...done.map((t) => _TodoTile(
                  item: t,
                  tag: _tagById(t.tagId),
                  isSelected: false,
                  onToggle: () => onToggle(t.id),
                  onDelete: () => onDelete(t.id),
                  onSelect: () {},
                )),
          ],
        ])),
      ]),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem item;
  final WorkTag? tag;
  final bool isSelected;
  final VoidCallback onToggle, onDelete, onSelect;

  const _TodoTile(
      {required this.item,
      required this.tag,
      required this.isSelected,
      required this.onToggle,
      required this.onDelete,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E2E2E) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFFE8724A).withOpacity(0.35), width: 1)
              : null,
        ),
        child: Row(children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: item.isCompleted
                        ? const Color(0xFF2564CF)
                        : Colors.white24,
                    width: 1.5),
                color: item.isCompleted
                    ? const Color(0xFF2564CF)
                    : Colors.transparent,
              ),
              child: item.isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 10)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(item.title,
                  style: TextStyle(
                    color: item.isCompleted ? Colors.white24 : Colors.white70,
                    fontSize: 13,
                    decoration:
                        item.isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white24,
                  ))),
          // Tag dot
          if (tag != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tag!.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tag!.color.withOpacity(0.4)),
              ),
              child: Text(tag!.name,
                  style: TextStyle(
                      color: tag!.color,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          if (isSelected) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.delete_outline,
                  color: Colors.white24, size: 14),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Tag Ranking Card ─────────────────────────────────────────────────────────

class _TagRankingCard extends StatelessWidget {
  final List<MapEntry<String?, int>> sorted;
  final List<WorkTag> tags;
  final int totalMinutes;
  final String Function(int) fmtDuration;

  const _TagRankingCard({
    required this.sorted,
    required this.tags,
    required this.totalMinutes,
    required this.fmtDuration,
  });

  WorkTag? _tagById(String? id) => id == null
      ? null
      : tags.firstWhere((t) => t.id == id,
          orElse: () => WorkTag(id: '', name: 'Untagged', color: Colors.grey));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Today's Tag Ranking",
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (sorted.isEmpty)
          const Center(
              child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No focus sessions today.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ))
        else
          ...sorted.take(5).map((e) {
            final tag = _tagById(e.key);
            final maxVal = sorted.first.value.toDouble();
            final frac = maxVal > 0 ? e.value / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tag?.name ?? 'Untagged',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      Text(fmtDuration(e.value),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(children: [
                    Container(
                        height: 6,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(3))),
                    FractionallySizedBox(
                      widthFactor: frac.clamp(0.0, 1.0),
                      child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                              color: (tag?.color ?? Colors.grey),
                              borderRadius: BorderRadius.circular(3))),
                    ),
                  ]),
                ],
              ),
            );
          }).toList(),
      ]),
    );
  }
}
