import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
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

class TodoItem {
  final String id;
  String title;
  bool isCompleted;
  TodoItem({required this.id, required this.title, this.isCompleted = false});
}

// ─── Focus Home Page ──────────────────────────────────────────────────────────

class FocusHomePage extends StatefulWidget {
  const FocusHomePage({super.key});

  @override
  State<FocusHomePage> createState() => _FocusHomePageState();
}

class _FocusHomePageState extends State<FocusHomePage> {
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

  final List<TodoItem> _todos = [
    TodoItem(id: '1', title: 'Review project proposal'),
    TodoItem(id: '2', title: 'Write weekly report'),
    TodoItem(id: '3', title: 'Team standup meeting'),
  ];
  final TextEditingController _todoController = TextEditingController();
  String? _selectedTaskId;

  Future<void> _togglePiP(bool enable) async {
    setState(() => _isPinned = enable);
    if (enable) {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setMinimizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setClosable(false);
      await windowManager.setSize(const Size(320, 360));
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setClosable(true);
      await windowManager.setSize(const Size(800, 600));
      await windowManager.center();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _todoController.dispose();
    super.dispose();
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
          _showCompletionDialog();
        }
      });
    });
  }

  void _stopSession() {
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

  String get _timeDisplay {
    if (!_isRunning) return '${_sessionMinutes.toString().padLeft(2, '0')}:00';
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _hasBreak => _breakMinutes > 0;

  void _addTodo() {
    final text = _todoController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _todos.add(TodoItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(), title: text));
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

  @override
  Widget build(BuildContext context) {
    // ── PiP mode: show compact overlay only ──
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
      );
    }

    final w = MediaQuery.of(context).size.width;
    final isWide = w > 700;

    return Scaffold(
      body: Container(
        color: const Color(0xFF1A1A1A),
        child: Padding(
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
                            onOpenSettings: () => _showSettingsSheet(context),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                              child: _TodoCard(
                            todos: _todos,
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
                      width: 320,
                      child: _DailyProgressCard(
                        yesterdayMinutes: _yesterdayMinutes,
                        dailyGoalHours: _dailyGoalHours,
                        streak: _streak,
                        completedMinutes: _completedToday,
                        progressFraction: _progressFraction,
                        onGoalChanged: (h) =>
                            setState(() => _dailyGoalHours = h),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _FocusCard(
                        sessionMinutes: _sessionMinutes,
                        isRunning: _isRunning,
                        timeDisplay: _timeDisplay,
                        hasBreak: _hasBreak,
                        isPinned: _isPinned,
                        onIncrement: _isRunning
                            ? null
                            : () => setState(() {
                                  if (_sessionMinutes < 240)
                                    _sessionMinutes += 5;
                                }),
                        onDecrement: _isRunning
                            ? null
                            : () => setState(() {
                                  if (_sessionMinutes > 5) _sessionMinutes -= 5;
                                }),
                        onStart: _startSession,
                        onTogglePin: () => _togglePiP(true),
                        onOpenSettings: () => _showSettingsSheet(context),
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
                      SizedBox(
                          height: 380,
                          child: _TodoCard(
                            todos: _todos,
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
        ),
      ),
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
              // ── Exit PiP (Subtle) ──
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

              // ── Timer + arrows ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        timeDisplay,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w200,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (!isRunning) ...[
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          _ArrowButton(
                              icon: Icons.keyboard_arrow_up,
                              onTap: onIncrement),
                          const SizedBox(height: 4),
                          _ArrowButton(
                              icon: Icons.keyboard_arrow_down,
                              onTap: onDecrement),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Break label ──
              Text(
                hasBreak ? 'Session includes a $breakMinutes min break' : 'No breaks',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),

              const SizedBox(height: 20),

              // ── Start button ──
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
  final VoidCallback? onIncrement, onDecrement;
  final VoidCallback onStart, onTogglePin, onOpenSettings;

  const _FocusCard({
    required this.sessionMinutes,
    required this.isRunning,
    required this.timeDisplay,
    required this.hasBreak,
    required this.isPinned,
    required this.onIncrement,
    required this.onDecrement,
    required this.onStart,
    required this.onTogglePin,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Get ready to focus',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Compact view',
                    child: GestureDetector(
                      onTap: onTogglePin,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.picture_in_picture_alt,
                            color: Colors.white54, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Settings',
                    child: GestureDetector(
                      onTap: onOpenSettings,
                      child: const Icon(Icons.more_horiz,
                          color: Colors.white54, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // const Text(
          //   "We'll turn off notifications and app alerts during each session.\nFor longer sessions, we'll add a short break so you can recharge.",
          //   textAlign: TextAlign.center,
          //   style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
          // ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Text(timeDisplay,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w300,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  if (!isRunning)
                    const Text('mins',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                ]),
              ),
              if (!isRunning) ...[
                const SizedBox(width: 8),
                Column(children: [
                  _ArrowButton(
                      icon: Icons.keyboard_arrow_up, onTap: onIncrement),
                  const SizedBox(height: 4),
                  _ArrowButton(
                      icon: Icons.keyboard_arrow_down, onTap: onDecrement),
                ]),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
              hasBreak
                  ? 'Session includes a short break'
                  : "You'll have no breaks",
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 18),
              label: Text(isRunning ? 'Stop session' : 'Start focus session',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8724A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Arrow Button ─────────────────────────────────────────────────────────────

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ArrowButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(6)),
        child: Icon(icon,
            color: onTap != null ? Colors.white70 : Colors.white24, size: 18),
      ),
    );
  }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final int sessionMinutes, breakMinutes;
  final bool endSessionSound, endBreakSound;
  final void Function(int session, int brk, bool sessSound, bool brkSound)
      onSave;

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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
            child: Row(
              children: [
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
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Focus sessions',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
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
              ),
            ),
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
              ),
            ),
          ],
          _SettingsTile(
            icon: Icons.alarm_outlined,
            title: 'End of session sound',
            subtitle: 'Play an alarm when focus period ends',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_sessSound ? 'On' : 'Off',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
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
                inactiveTrackColor: Colors.white12,
              ),
            ]),
          ),
          _SettingsTile(
            icon: Icons.alarm_outlined,
            title: 'End of break sound',
            subtitle: 'Play an alarm when breaks end',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_brkSound ? 'On' : 'Off',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
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
                inactiveTrackColor: Colors.white12,
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
      ),
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
      child: Row(
        children: [
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
            ]),
          ),
          trailing,
        ],
      ),
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
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
          child,
        ],
      ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daily progress',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: () => _showGoalDialog(context),
                child: const Icon(Icons.edit_outlined,
                    color: Colors.white54, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatColumn(
                  label: 'Yesterday',
                  value: yesterdayMinutes.toString(),
                  unit: 'minutes'),
              _ProgressRing(
                  fraction: progressFraction,
                  centerLabel: dailyGoalHours.toString(),
                  centerSub: 'hours',
                  topLabel: 'Daily goal'),
              _StatColumn(
                  label: 'Streak', value: streak.toString(), unit: 'days'),
            ],
          ),
          const SizedBox(height: 20),
          Center(
              child: Text('Completed: $completedMinutes minutes',
                  style: const TextStyle(color: Colors.white54, fontSize: 13))),
        ],
      ),
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
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setS(() {
                  if (tempGoal > 1) tempGoal--;
                }),
                icon: const Icon(Icons.remove, color: Colors.white70),
              ),
              Text('$tempGoal hrs',
                  style: const TextStyle(color: Colors.white, fontSize: 22)),
              IconButton(
                onPressed: () => setS(() {
                  if (tempGoal < 16) tempGoal++;
                }),
                icon: const Icon(Icons.add, color: Colors.white70),
              ),
            ],
          ),
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
                  style: TextStyle(color: Color(0xFFE8724A))),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label, value, unit;
  const _StatColumn(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300)),
        Text(unit, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
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
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 8),
      SizedBox(
        width: 110,
        height: 110,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
                size: const Size(110, 110),
                painter: _RingPainter(fraction: fraction)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(centerLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w300)),
              Text(centerSub,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ],
        ),
      ),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  const _RingPainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF3A3A3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
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
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

// ─── Todo Card ────────────────────────────────────────────────────────────────

class _TodoCard extends StatelessWidget {
  final List<TodoItem> todos;
  final TextEditingController controller;
  final String? selectedTaskId;
  final VoidCallback onAdd;
  final ValueChanged<String> onToggle, onDelete;
  final ValueChanged<String?> onSelect;

  const _TodoCard({
    required this.todos,
    required this.controller,
    required this.selectedTaskId,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final pending = todos.where((t) => !t.isCompleted).toList();
    final done = todos.where((t) => t.isCompleted).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  color: const Color(0xFF2564CF),
                  borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.check, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
            const Text('To Do',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${pending.length} remaining',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add a task...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon:
                    const Icon(Icons.add, color: Colors.white38, size: 18),
              ),
              onSubmitted: (_) => onAdd(),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8724A),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
              child: ListView(children: [
            ...pending.map((t) => _TodoTile(
                  item: t,
                  isSelected: selectedTaskId == t.id,
                  onToggle: () => onToggle(t.id),
                  onDelete: () => onDelete(t.id),
                  onSelect: () =>
                      onSelect(selectedTaskId == t.id ? null : t.id),
                )),
            if (done.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Completed',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              ...done.map((t) => _TodoTile(
                    item: t,
                    isSelected: false,
                    onToggle: () => onToggle(t.id),
                    onDelete: () => onDelete(t.id),
                    onSelect: () {},
                  )),
            ],
          ])),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem item;
  final bool isSelected;
  final VoidCallback onToggle, onDelete, onSelect;

  const _TodoTile(
      {required this.item,
      required this.isSelected,
      required this.onToggle,
      required this.onDelete,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E2E2E) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFFE8724A).withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: item.isCompleted
                        ? const Color(0xFF2564CF)
                        : Colors.white38,
                    width: 1.5),
                color: item.isCompleted
                    ? const Color(0xFF2564CF)
                    : Colors.transparent,
              ),
              child: item.isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(item.title,
                  style: TextStyle(
                    color: item.isCompleted ? Colors.white38 : Colors.white70,
                    fontSize: 14,
                    decoration:
                        item.isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white38,
                  ))),
          if (isSelected)
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 16),
            ),
        ]),
      ),
    );
  }
}
