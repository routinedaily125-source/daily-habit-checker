import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// ============================================================================
/// 1. APPLICATION ENTRY POINT & SERVICES INITIALIZATION
/// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Google Mobile Ads SDK
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint('MobileAds initialization error: $e');
  }

  // Initialize Local Notifications & Timezone database
  await NotificationService.init();

  runApp(const DailyHabitApp());
}

/// Root Application Widget configuring Material 3 design and dynamic theming.
class DailyHabitApp extends StatefulWidget {
  const DailyHabitApp({super.key});

  static _DailyHabitAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_DailyHabitAppState>();

  @override
  State<DailyHabitApp> createState() => _DailyHabitAppState();
}

class _DailyHabitAppState extends State<DailyHabitApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('app_is_dark_mode');
      if (isDark != null) {
        setState(() {
          _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
        });
      }
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
    }
  }

  void toggleTheme(bool isDark) async {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_is_dark_mode', isDark);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Habit Checker',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D6B56), // Fresh Emerald Green
          brightness: Brightness.light,
        ),
        cardTheme: const CardTheme(
          elevation: 0,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D6B56),
          brightness: Brightness.dark,
        ),
      ),
      home: const HabitHomeScreen(),
    );
  }
}

/// ============================================================================
/// 2. NOTIFICATION SERVICE (flutter_local_notifications & timezone)
/// ============================================================================
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize notification channels, permissions, and timezone engine
  static Future<void> init() async {
    try {
      tz.initializeTimeZones();

      // Android Notification Settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS / Darwin Notification Settings
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification clicked with payload: ${response.payload}');
        },
      );

      // Request runtime notification permissions for Android 13+
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Error initializing notification service: $e');
    }
  }

  /// Schedules a recurring daily alarm/notification for a habit at a specific hour & minute
  static Future<void> scheduleDailyHabitNotification({
    required int id,
    required String title,
    required String category,
    required int hour,
    required int minute,
  }) async {
    try {
      final scheduledDate = _nextInstanceOfTime(hour, minute);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'daily_habit_reminders_channel',
        'Daily Habit Reminders',
        channelDescription: 'Scheduled alarms and reminders for completing daily habits',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Habit Reminder',
        playSound: true,
        enableVibration: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.zonedSchedule(
        id,
        '⏰ Time for your habit: $title',
        'Keep up your $category streak! Mark it as completed in Daily Habit Checker.',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // Repeats daily at this exact time
        payload: 'habit_$id',
      );

      debugPrint('Successfully scheduled daily notification for $title at $hour:${minute.toString().padLeft(2, '0')}');
    } catch (e) {
      debugPrint('Failed to schedule daily notification: $e');
    }
  }

  /// Cancels an existing scheduled notification
  static Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('Error canceling notification $id: $e');
    }
  }

  /// Calculates the next occurrence of the specified hour and minute in the local timezone
  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the scheduled time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}

/// ============================================================================
/// 3. GOOGLE ADMOB SERVICE (google_mobile_ads)
/// ============================================================================
class AdMobService {
  /// Official Google AdMob Sample / Test Banner Ad Unit IDs
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      // Official Google sample test ad unit ID for Android Banner
      return 'ca-app-pub-3940256099942544/6300978111';
    } else if (Platform.isIOS) {
      // Official Google sample test ad unit ID for iOS Banner
      return 'ca-app-pub-3940256099942544/2934735716';
    } else {
      return 'ca-app-pub-3940256099942544/6300978111';
    }
  }
}

/// ============================================================================
/// 4. MODELS & DATA STRUCTURES
/// ============================================================================
class HabitCategory {
  final String name;
  final IconData icon;

  const HabitCategory({required this.name, required this.icon});
}

/// Expanded Category List with 10 rich lifestyle options
const List<HabitCategory> kHabitCategories = [
  HabitCategory(name: 'Health', icon: Icons.favorite_outline),
  HabitCategory(name: 'Fitness', icon: Icons.fitness_center_outlined),
  HabitCategory(name: 'Productivity', icon: Icons.bolt_outlined),
  HabitCategory(name: 'Learning', icon: Icons.menu_book_outlined),
  HabitCategory(name: 'Mindfulness', icon: Icons.self_improvement_outlined),
  HabitCategory(name: 'Finance', icon: Icons.savings_outlined),
  HabitCategory(name: 'Career', icon: Icons.work_outline),
  HabitCategory(name: 'Spirituality', icon: Icons.spa_outlined),
  HabitCategory(name: 'Relationship', icon: Icons.people_outline),
  HabitCategory(name: 'Personal Care', icon: Icons.clean_hands_outlined),
];

/// Helper function to map habit category or title keywords to modern Material symbols
IconData resolveHabitIcon(String title, String category) {
  final cat = category.toLowerCase();
  final t = title.toLowerCase();

  if (cat == 'health' || t.contains('water') || t.contains('drink') || t.contains('diet') || t.contains('eat')) {
    return Icons.favorite_outline;
  } else if (cat == 'fitness' || t.contains('run') || t.contains('gym') || t.contains('workout') || t.contains('jog')) {
    return Icons.fitness_center_outlined;
  } else if (cat == 'productivity' || t.contains('task') || t.contains('focus') || t.contains('deep work')) {
    return Icons.bolt_outlined;
  } else if (cat == 'learning' || t.contains('read') || t.contains('book') || t.contains('study') || t.contains('code')) {
    return Icons.menu_book_outlined;
  } else if (cat == 'mindfulness' || t.contains('meditat') || t.contains('breath') || t.contains('yoga')) {
    return Icons.self_improvement_outlined;
  } else if (cat == 'finance' || t.contains('money') || t.contains('save') || t.contains('budget') || t.contains('invest')) {
    return Icons.savings_outlined;
  } else if (cat == 'career' || t.contains('job') || t.contains('resume') || t.contains('meeting')) {
    return Icons.work_outline;
  } else if (cat == 'spirituality' || t.contains('pray') || t.contains('gratitude')) {
    return Icons.spa_outlined;
  } else if (cat == 'relationship' || t.contains('family') || t.contains('call') || t.contains('friend')) {
    return Icons.people_outline;
  } else if (cat == 'personal care' || t.contains('sleep') || t.contains('bed') || t.contains('skin') || t.contains('bath')) {
    return Icons.clean_hands_outlined;
  } else {
    return Icons.check_circle_outline;
  }
}

/// Data Model representing a single trackable habit item.
class Habit {
  final int notificationId;
  final String id;
  final String title;
  final String category;
  final String time; // e.g., "07:00 AM"
  final int hour;
  final int minute;
  final IconData icon;
  bool isCompleted;

  Habit({
    required this.notificationId,
    required this.id,
    required this.title,
    required this.category,
    required this.time,
    required this.hour,
    required this.minute,
    required this.icon,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'notificationId': notificationId,
      'id': id,
      'title': title,
      'category': category,
      'time': time,
      'hour': hour,
      'minute': minute,
      'isCompleted': isCompleted,
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    final title = map['title'] as String? ?? '';
    final category = map['category'] as String? ?? 'Health';
    final time = map['time'] as String? ?? '07:00 AM';
    final hour = map['hour'] as int? ?? 7;
    final minute = map['minute'] as int? ?? 0;
    final notifId = map['notificationId'] as int? ?? (DateTime.now().millisecondsSinceEpoch % 100000);

    return Habit(
      notificationId: notifId,
      id: map['id'] as String? ?? UniqueKey().toString(),
      title: title,
      category: category,
      time: time,
      hour: hour,
      minute: minute,
      icon: resolveHabitIcon(title, category),
      isCompleted: map['isCompleted'] as bool? ?? false,
    );
  }
}

/// ============================================================================
/// 5. MAIN HABIT LIST SCREEN WITH STATE, ADMOB BANNER, & PERSISTENCE
/// ============================================================================
class HabitHomeScreen extends StatefulWidget {
  const HabitHomeScreen({super.key});

  @override
  State<HabitHomeScreen> createState() => _HabitHomeScreenState();
}

class _HabitHomeScreenState extends State<HabitHomeScreen> {
  static const String _storageKey = 'daily_habits_storage_v3';

  List<Habit> _habits = [];
  bool _isLoading = true;
  String _profileName = 'Habit Champion';
  DateTime? _profileDob = DateTime(1998, 5, 20);

  // Calculates user age in full years based on current date
  int? get _userAge {
    if (_profileDob == null) return null;
    final now = DateTime.now();
    int age = now.year - _profileDob!.year;
    if (now.month < _profileDob!.month ||
        (now.month == _profileDob!.month && now.day < _profileDob!.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  // Important Notebook state
  String _notebookText = '';
  String? _notebookLastUpdated;
  final TextEditingController _notebookController = TextEditingController();
  bool _isNotebookSaving = false;

  // Google AdMob Banner state
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHabitsFromStorage();
    _initBannerAd();
  }

  @override
  void dispose() {
    _notebookController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  /// Initializes and loads the Google AdMob Banner Ad
  void _initBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdMobService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Google AdMob Banner Ad successfully loaded.');
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Google AdMob Banner Ad failed to load: $error');
          ad.dispose();
        },
      ),
    );

    _bannerAd?.load();
  }

  /// Saves the Important Notebook text to SharedPreferences
  Future<void> _saveNotebook(String text) async {
    setState(() {
      _isNotebookSaving = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('important_notebook_text', text);
      final nowFormatted = DateFormat('MMM d, h:mm a').format(DateTime.now());
      await prefs.setString('important_notebook_updated_at', nowFormatted);

      setState(() {
        _notebookText = text;
        _notebookLastUpdated = nowFormatted;
        _isNotebookSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              text.trim().isEmpty
                  ? 'Notebook cleared! 📝'
                  : 'Important Notebook saved! 📝',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving notebook: $e');
      setState(() {
        _isNotebookSaving = false;
      });
    }
  }

  /// Loads habits and user profile from SharedPreferences and ensures scheduled notifications exist
  Future<void> _loadHabitsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load saved profile name
      final savedName = prefs.getString('user_profile_name');
      if (savedName != null && savedName.trim().isNotEmpty) {
        _profileName = savedName.trim();
      }

      // Load saved Date of Birth
      final savedDob = prefs.getString('user_profile_dob');
      if (savedDob != null && savedDob.trim().isNotEmpty) {
        try {
          _profileDob = DateTime.parse(savedDob);
        } catch (e) {
          debugPrint('Error parsing stored DOB: $e');
        }
      }

      // Load saved Important Notebook
      final savedNote = prefs.getString('important_notebook_text');
      if (savedNote != null) {
        _notebookText = savedNote;
        _notebookController.text = savedNote;
      }
      _notebookLastUpdated = prefs.getString('important_notebook_updated_at');

      final String? storedJson = prefs.getString(_storageKey);

      if (storedJson != null && storedJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(storedJson);
        setState(() {
          _habits = decoded
              .map((item) => Habit.fromMap(item as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading habits from SharedPreferences: $e');
    }

    // Default habits on first install
    final defaultHabits = [
      Habit(
        notificationId: 101,
        id: '1',
        title: 'Drink 2L Water',
        category: 'Health',
        time: '08:00 AM',
        hour: 8,
        minute: 0,
        icon: Icons.favorite_outline,
        isCompleted: true,
      ),
      Habit(
        notificationId: 102,
        id: '2',
        title: 'Morning Yoga / Run',
        category: 'Fitness',
        time: '07:00 AM',
        hour: 7,
        minute: 0,
        icon: Icons.fitness_center_outlined,
        isCompleted: false,
      ),
      Habit(
        notificationId: 103,
        id: '3',
        title: 'Deep Work Sprint',
        category: 'Productivity',
        time: '10:00 AM',
        hour: 10,
        minute: 0,
        icon: Icons.bolt_outlined,
        isCompleted: false,
      ),
      Habit(
        notificationId: 104,
        id: '4',
        title: 'Read 20 Pages',
        category: 'Learning',
        time: '09:30 PM',
        hour: 21,
        minute: 30,
        icon: Icons.menu_book_outlined,
        isCompleted: false,
      ),
      Habit(
        notificationId: 105,
        id: '5',
        title: 'Mindful Meditation',
        category: 'Mindfulness',
        time: '06:30 AM',
        hour: 6,
        minute: 30,
        icon: Icons.self_improvement_outlined,
        isCompleted: true,
      ),
      Habit(
        notificationId: 106,
        id: '6',
        title: 'Review Daily Budget',
        category: 'Finance',
        time: '08:30 PM',
        hour: 20,
        minute: 30,
        icon: Icons.savings_outlined,
        isCompleted: false,
      ),
      Habit(
        notificationId: 107,
        id: '7',
        title: 'Night Skincare & Rest',
        category: 'Personal Care',
        time: '10:30 PM',
        hour: 22,
        minute: 30,
        icon: Icons.clean_hands_outlined,
        isCompleted: false,
      ),
    ];

    setState(() {
      _habits = defaultHabits;
      _isLoading = false;
    });

    // Schedule daily alarms for initial habits
    for (final habit in defaultHabits) {
      NotificationService.scheduleDailyHabitNotification(
        id: habit.notificationId,
        title: habit.title,
        category: habit.category,
        hour: habit.hour,
        minute: habit.minute,
      );
    }

    _persistHabits();
  }

  /// Persists current habits to local storage
  Future<void> _persistHabits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> mapList = _habits.map((h) => h.toMap()).toList();
      await prefs.setString(_storageKey, jsonEncode(mapList));
    } catch (e) {
      debugPrint('Error saving habits: $e');
    }
  }

  /// Format TimeOfDay into readable 12-hour AM/PM string
  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  /// Format current date into Day Name (e.g., "Saturday")
  String get _currentDayName {
    try {
      return DateFormat('EEEE').format(DateTime.now());
    } catch (_) {
      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      return weekdays[DateTime.now().weekday - 1];
    }
  }

  /// Format current date into Full Date (e.g., "September 12, 2026")
  String get _currentFormattedDate {
    try {
      return DateFormat('MMMM d, yyyy').format(DateTime.now());
    } catch (_) {
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      final now = DateTime.now();
      return '${months[now.month - 1]} ${now.day}, ${now.year}';
    }
  }

  /// Toggle habit completion status
  void _toggleHabit(int index) {
    setState(() {
      _habits[index].isCompleted = !_habits[index].isCompleted;
    });

    _persistHabits();

    final habit = _habits[index];
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          habit.isCompleted
              ? 'Completed: "${habit.title}" 🎉'
              : 'Marked "${habit.title}" as incomplete',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Add Habit Dialog with Categories, Time Picker, and Daily Alarm Scheduling
  void _showAddHabitDialog() {
    final titleController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String selectedCategory = 'Health';
    TimeOfDay selectedTime = const TimeOfDay(hour: 7, minute: 0);

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.alarm_add, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('New Daily Habit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                ],
              ),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set up your routine with a category and daily reminder alarm.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),

                        // Habit Title Input
                        TextFormField(
                          controller: titleController,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Habit Name *',
                            hintText: 'e.g., Morning Meditation, Gym',
                            prefixIcon: const Icon(Icons.edit_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a habit name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Daily Reminder Time Picker (Sets Local Notification Alarm)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Scheduled Alarm Time',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Daily Notification',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                              helpText: 'SELECT DAILY HABIT ALARM TIME',
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedTime = picked;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.alarm,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Daily Alarm',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTimeOfDay(selectedTime),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Chip(
                                  label: const Text('Change', style: TextStyle(fontSize: 12)),
                                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                                  backgroundColor: theme.colorScheme.surface,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Category Selector (10 Rich Options)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Select Category',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              selectedCategory,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kHabitCategories.map((cat) {
                            final isSelected = selectedCategory == cat.name;
                            return ChoiceChip(
                              avatar: Icon(
                                cat.icon,
                                size: 16,
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              label: Text(cat.name, style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              selectedColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setDialogState(() {
                                    selectedCategory = cat.name;
                                  });
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save & Schedule'),
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      final name = titleController.text.trim();
                      final timeStr = _formatTimeOfDay(selectedTime);
                      final icon = resolveHabitIcon(name, selectedCategory);
                      final notificationId =
                          (DateTime.now().millisecondsSinceEpoch % 100000).toInt();

                      final newHabit = Habit(
                        notificationId: notificationId,
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: name,
                        category: selectedCategory,
                        time: timeStr,
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        icon: icon,
                        isCompleted: false,
                      );

                      setState(() {
                        _habits.add(newHabit);
                      });

                      // Schedule Daily Local Notification & Alarm
                      NotificationService.scheduleDailyHabitNotification(
                        id: notificationId,
                        title: name,
                        category: selectedCategory,
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                      );

                      // Persist to local storage
                      _persistHabits();

                      Navigator.of(ctx).pop();

                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Scheduled daily alarm for "$name" at $timeStr! 🔔'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialName: _profileName,
          initialDob: _profileDob,
          onProfileUpdated: (newName, newDob) {
            setState(() {
              _profileName = newName;
              _profileDob = newDob;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final completedCount = _habits.where((h) => h.isCompleted).length;
    final totalCount = _habits.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Daily Habit Checker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _navigateToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Prominent User Profile & Dynamic Date Header Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User Greeting & DOB row + Streak Counter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _navigateToSettings,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: theme.colorScheme.primaryContainer,
                                      child: Text(
                                        _profileName.isNotEmpty ? _profileName[0].toUpperCase() : 'U',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Hello, $_profileName 👋',
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.cake_outlined,
                                                size: 13,
                                                color: theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  _profileDob != null
                                                      ? 'DOB: ${DateFormat('MMM d, yyyy').format(_profileDob!)}${_userAge != null ? ' (${_userAge}y)' : ''}'
                                                      : 'Tap to set DOB',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '5d Streak',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Dynamic Calendar Date & Day row
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _currentDayName.toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: theme.colorScheme.outlineVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            _currentFormattedDate,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Dynamic Daily Progress Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Card(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Today's Progress",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            totalCount > 0 && completedCount == totalCount
                                ? 'All habits completed today! 🌟'
                                : '$completedCount of $totalCount habits completed',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: theme.colorScheme.surface,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // ListView displaying habits followed by the Important Notebook section
                Expanded(
                  child: ListView.builder(
                    itemCount: _habits.length + 1,
                    padding: const EdgeInsets.only(bottom: 96),
                    itemBuilder: (context, index) {
                      if (index < _habits.length) {
                        final habit = _habits[index];
                        return HabitListTile(
                          habit: habit,
                          onChanged: (_) => _toggleHabit(index),
                        );
                      }
                      // Important Notebook / Quick Notes Section right below habits
                      return ImportantNotebookWidget(
                        controller: _notebookController,
                        lastUpdated: _notebookLastUpdated,
                        isSaving: _isNotebookSaving,
                        onSave: (text) => _saveNotebook(text),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddHabitDialog,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        tooltip: 'Add Habit',
        icon: const Icon(Icons.add_alarm),
        label: const Text('New Habit', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      // Clean, persistent Google AdMob Banner Container at screen bottom
      bottomNavigationBar: SafeArea(
        child: Container(
          color: theme.colorScheme.surfaceContainerLowest,
          width: double.infinity,
          height: 60,
          alignment: Alignment.center,
          child: _isBannerAdLoaded && _bannerAd != null
              ? SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                )
              : Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Ad',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Google AdMob Test Banner Ready (320x50)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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

/// ============================================================================
/// 6. HABIT LIST TILE COMPONENT
/// ============================================================================
class HabitListTile extends StatelessWidget {
  final Habit habit;
  final ValueChanged<bool?> onChanged;

  const HabitListTile({
    super.key,
    required this.habit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = habit.isCompleted;

    return Card(
      color: isDone
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDone
              ? Colors.transparent
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isDone
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
              : theme.colorScheme.primaryContainer,
          child: Icon(
            habit.icon,
            size: 22,
            color: isDone ? theme.colorScheme.outline : theme.colorScheme.primary,
          ),
        ),
        title: Text(
          habit.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? theme.colorScheme.outline : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              // Category Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDone
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  habit.category,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDone
                        ? theme.colorScheme.outline
                        : theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Scheduled Daily Alarm Badge
              Icon(
                Icons.alarm,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                habit.time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        trailing: Checkbox(
          value: isDone,
          onChanged: onChanged,
          activeColor: theme.colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        onTap: () => onChanged(!isDone),
      ),
    );
  }
}

/// ============================================================================
/// 7. FULLY FUNCTIONAL SETTINGS SCREEN
/// ============================================================================
class SettingsScreen extends StatefulWidget {
  final String initialName;
  final DateTime? initialDob;
  final void Function(String newName, DateTime? newDob) onProfileUpdated;

  const SettingsScreen({
    super.key,
    required this.initialName,
    required this.initialDob,
    required this.onProfileUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _currentName;
  DateTime? _currentDob;
  static const String _versionString = 'Version 1.0.0 (Build 1)';

  @override
  void initState() {
    super.initState();
    _currentName = widget.initialName;
    _currentDob = widget.initialDob;
  }

  // Calculate user age in years
  int? get _currentAge {
    if (_currentDob == null) return null;
    final now = DateTime.now();
    int age = now.year - _currentDob!.year;
    if (now.month < _currentDob!.month ||
        (now.month == _currentDob!.month && now.day < _currentDob!.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  int _calculateAgeForDate(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  /// Opens an AlertDialog to edit the user's profile name and Date of Birth
  void _showEditProfileDialog() {
    final controller = TextEditingController(text: _currentName);
    final formKey = GlobalKey<FormState>();
    DateTime? tempDob = _currentDob;

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final dialogAge = tempDob != null ? _calculateAgeForDate(tempDob!) : null;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_pin_outlined, size: 20, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('Edit Profile & DOB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your profile name and date of birth appear at the top of your habit dashboard.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Profile Name *',
                          hintText: 'e.g., Alex, Champion',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.person_outline),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your profile name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Date of Birth',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogCtx,
                            initialDate: tempDob ?? DateTime(1998, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                            helpText: 'SELECT DATE OF BIRTH',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              tempDob = picked;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.cake_outlined,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tempDob != null
                                          ? DateFormat('MMMM d, yyyy').format(tempDob!)
                                          : 'Select Date of Birth',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    if (dialogAge != null)
                                      Text(
                                        '$dialogAge years old',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Chip(
                                label: const Text('Select', style: TextStyle(fontSize: 12)),
                                side: BorderSide(color: theme.colorScheme.outlineVariant),
                                backgroundColor: theme.colorScheme.surface,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save Profile'),
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final newName = controller.text.trim();
                      setState(() {
                        _currentName = newName;
                        _currentDob = tempDob;
                      });
                      widget.onProfileUpdated(newName, tempDob);

                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('user_profile_name', newName);
                        if (tempDob != null) {
                          await prefs.setString('user_profile_dob', tempDob!.toIso8601String());
                        } else {
                          await prefs.remove('user_profile_dob');
                        }
                      } catch (e) {
                        debugPrint('Error saving profile: $e');
                      }

                      if (ctx.mounted) Navigator.of(ctx).pop();

                      if (mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Profile updated! "$newName"${tempDob != null ? ' (DOB: ${DateFormat('MMM d, yyyy').format(tempDob!)})' : ''} ✨',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = DailyHabitApp.of(context);
    final isDark = appState?.isDarkMode(context) ?? (theme.brightness == Brightness.dark);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // 1. Profile Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
            child: Text(
              'ACCOUNT & PROFILE',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      _currentName.isNotEmpty ? _currentName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Personalized Daily Habit User',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.cake_outlined, size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _currentDob != null
                                    ? 'DOB: ${DateFormat('MMM d, yyyy').format(_currentDob!)}${_currentAge != null ? ' • $_currentAge yrs old' : ''}'
                                    : 'DOB: Not set',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // 2. Preferences & Theme Toggle Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
            child: Text(
              'APPEARANCE & THEME',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: theme.colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    isDark ? 'Dark theme is currently active' : 'Light theme is currently active',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  value: isDark,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (val) {
                    appState?.toggleTheme(val);
                  },
                ),
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: const Text('Habit Alarm Reminders', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Daily local alerts via flutter_local_notifications',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Chip(
                    label: const Text('Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. About Application Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
            child: Text(
              'ABOUT APPLICATION',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: theme.colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: const Text('App Version', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Daily Habit Checker'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _versionString,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: const Text('Design System', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Material Design 3 (M3) with Flutter'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Data & Local Persistence Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
            child: Text(
              'DATA & LOCAL STORAGE',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: theme.colorScheme.surfaceContainerLow,
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.save_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: const Text('Local Persistence', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Habits, Profile, DOB & Notebook saved locally via SharedPreferences'),
              trailing: Chip(
                label: const Text('Offline Ready', style: TextStyle(fontSize: 11)),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 8. IMPORTANT NOTEBOOK / QUICK NOTES COMPONENT
/// ============================================================================
class ImportantNotebookWidget extends StatefulWidget {
  final TextEditingController controller;
  final String? lastUpdated;
  final bool isSaving;
  final ValueChanged<String> onSave;

  const ImportantNotebookWidget({
    super.key,
    required this.controller,
    required this.lastUpdated,
    required this.isSaving,
    required this.onSave,
  });

  @override
  State<ImportantNotebookWidget> createState() => _ImportantNotebookWidgetState();
}

class _ImportantNotebookWidgetState extends State<ImportantNotebookWidget> {
  final List<String> _quickPrompts = [
    '💡 Key Idea',
    '🎯 Priority',
    '🧘 Gratitude',
    '📝 Daily Reflection',
  ];

  void _appendPrompt(String prompt) {
    final current = widget.controller.text;
    final prefix = current.isEmpty || current.endsWith('\n') ? '' : '\n';
    final newText = '$current$prefix$prompt: ';
    widget.controller.text = newText;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notebook Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Important Notebook',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Quick Notes',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.lastUpdated != null
                            ? 'Last saved: ${widget.lastUpdated}'
                            : 'Write down key thoughts, priorities & reflections',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Quick Prompt Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickPrompts.map((prompt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ActionChip(
                      label: Text(prompt, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      backgroundColor: theme.colorScheme.surface,
                      onPressed: () => _appendPrompt(prompt),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 10),

            // Multiline Note Input
            TextField(
              controller: widget.controller,
              maxLines: 5,
              minLines: 3,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Type your daily thoughts, priority notes, or habit reflections here...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Action Row: Clear button & Save Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.controller.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      widget.controller.clear();
                      widget.onSave('');
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: theme.colorScheme.error,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                FilledButton.tonalIcon(
                  onPressed: widget.isSaving
                      ? null
                      : () => widget.onSave(widget.controller.text),
                  icon: widget.isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    widget.isSaving ? 'Saving...' : 'Save Note',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
