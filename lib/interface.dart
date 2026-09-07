part of 'main.dart';

bool get tamilUi =>
    Hive.isBoxOpen('settings') &&
    settingText('languageMode', 'English') == 'Tamil';
String ui(String value) => tamilUi ? (_tamilLabels[value] ?? value) : value;

// Keep display labels separate from stored names, roles and record values.
const _tamilLabels = <String, String>{
  'Home': 'முகப்பு',
  'Cows': 'மாடுகள்',
  'Calves': 'கன்றுகள்',
  'Sell': 'விற்பனை',
  'Sales': 'விற்பனை',
  'Reports': 'ரிப்போர்ட்',
  'Chat': 'சாட்',
  'Messages': 'மெசேஜ்கள்',
  'Tasks': 'வேலைகள்',
  'Settings': 'செட்டிங்ஸ்',
  'Info': 'உதவி',
  'Language': 'மொழி',
  'Notifications': 'அறிவிப்புகள்',
  'Mark all read': 'எல்லாத்தையும் பார்த்ததாக வை',
  'No notifications': 'அறிவிப்பு எதுவும் இல்லை',
  'New entry': 'புதிய பதிவு',
  'Add entry': 'பதிவு போடு',
  'Recent entries': 'கடைசி பதிவுகள்',
  'Entry actions': 'பதிவுகள்',
  'Cancel': 'வேண்டாம்',
  'Done': 'முடிச்சாச்சு',
  'Save': 'சேமி',
  'Assign': 'வேலை கொடு',
  'New task': 'புதிய வேலை',
  'Task': 'செய்ய வேண்டிய வேலை',
  'Assign to': 'யாருக்கு',
  'Due date': 'முடிக்க வேண்டிய நாள்',
  'Target time': 'முடிக்க வேண்டிய நேரம்',
  'Note': 'குறிப்பு',
  'Message': 'மெசேஜ்',
  'Delete message': 'மெசேஜை நீக்கு',
  'Delete this message?': 'இந்த மெசேஜை நீக்கலாமா?',
  'This removes the message for everyone in the ranch.':
      'இந்த மெசேஜ் ராஞ்சில் உள்ள எல்லாருக்கும் நீக்கப்படும்.',
  'Delete': 'நீக்கு',
  'Message deleted': 'மெசேஜ் நீக்கப்பட்டது',
  'Unable to delete. Try again.': 'நீக்க முடியல. மறுபடியும் முயற்சி பண்ணுங்க.',
  'Voice message': 'குரல் மெசேஜ்',
  'Record voice message': 'குரல் மெசேஜ் பதிவு செய்',
  'Send voice message': 'குரல் மெசேஜை அனுப்பு',
  'Cancel recording': 'பதிவை வேண்டாம்',
  'Microphone permission is needed': 'மைக் அனுமதி தேவை',
  'Unable to record. Try again.':
      'குரலை பதிவு செய்ய முடியல. மறுபடியும் முயற்சி பண்ணுங்க.',
  'Voice messages need an internet connection':
      'குரல் மெசேஜுக்கு இன்டர்நெட் தேவை.',
  'Voice message is too long':
      'குரல் மெசேஜ் ரொம்ப நீளமா இருக்கு. மறுபடியும் பதிவு பண்ணுங்க.',
  'Send': 'அனுப்பு',
  'Assigned': 'வேலை கொடுத்தாச்சு',
  'Completed': 'முடிச்சாச்சு',
  'Open': 'முடிக்க வேண்டியது',
  'No messages': 'மெசேஜ் எதுவும் இல்லை',
  'No tasks': 'வேலை எதுவும் இல்லை',
  'Task title is required': 'என்ன வேலைன்னு எழுதுங்க',
  'Unable to save. Try again.': 'சேமிக்க முடியல. மறுபடியும் முயற்சி பண்ணுங்க.',
  'Unable to load members': 'ஆட்கள் பட்டியல் வரல',
  'Retry': 'மீண்டும் முயற்சி',
  'App Settings': 'ஆப் செட்டிங்ஸ்',
  'Family Users': 'வீட்டு ஆட்கள்',
  'Ranch': 'பண்ணை',
  'Data': 'பதிவுகள்',
  'Cloud Sync': 'கிளவுட் சிங்க்',
  'Works Offline': 'இன்டர்நெட் இல்லாமலும் வேலை செய்யும்',
  'Export and Backup': 'எக்ஸ்போர்ட் / பேக்கப்',
  'Restore Backup': 'பேக்கப்பை திரும்ப எடு',
  'Sign Out': 'வெளியேறு',
  'Export': 'எக்ஸ்போர்ட்',
  'Full Backup': 'முழு பேக்கப்',
  'All Data - Excel Workbook': 'அனைத்து தரவு — Excel',
  'Individual files': 'தனித்தனி கோப்புகள்',
  'Animals': 'கால்நடைகள்',
  'Milk Records': 'பால் பதிவுகள்',
  'Expenses': 'செலவுகள்',
  'Milk': 'பால்',
  'Stock': 'இருப்பு',
  'Overview': 'முழு விவரம்',
  'Health': 'மருத்துவம்',
  'Timeline': 'டைம்லைன்',
  'Cow Profile': 'மாடு விவரம்',
  'Calf Profile': 'கன்று விவரம்',
  'All Cows': 'அனைத்து மாடுகள்',
  'All Calves': 'அனைத்து கன்றுகள்',
  'Cows & Calves': 'மாடுகள் மற்றும் கன்றுகள்',
  'Today': 'இன்று',
  'Yesterday': 'நேற்று',
  'This Month': 'இந்த மாதம்',
  'Last Month': 'கடந்த மாதம்',
  'All': 'அனைத்தும்',
  'Month': 'மாதம்',
  'Daily Report': 'இன்றைய ரிப்போர்ட்',
  'Monthly Report': 'மாத ரிப்போர்ட்',
  'Overall Report': 'முழு ரிப்போர்ட்',
  'Total Cows': 'மொத்த மாடுகள்',
  'Total Calves': 'மொத்த கன்றுகள்',
  'Total Milk': 'மொத்த பால்',
  'Income': 'வருமானம்',
  'Expense': 'செலவு',
  'Profit': 'லாபம்',
  'Pregnant Cows': 'சினை மாடுகள்',
  'Today Milk': 'இன்றைய பால்',
  'Last Entry': 'கடைசி பதிவு',
  'Lactation': 'கறவைக் காலம்',
  'Last Doctor Visit': 'கடைசியாக டாக்டர் பார்த்தது',
  'Notes': 'குறிப்புகள்',
  'Pregnancy Duration': 'சினைக் காலம்',
  'Pregnancy Injection': 'சினை ஊசி',
  'Milking Stopped': 'பால் கறப்பது நிறுத்தப்பட்டது',
  'Add Milk Record': 'பால் பதிவு சேர்',
  'Add Doctor Visit': 'டாக்டர் பதிவு போடு',
  'Stop Milking': 'பால் கறப்பதை நிறுத்து',
  'Calf Born': 'கன்று பிறந்தது',
  'Milk History': 'பால் வரலாறு',
  'Health Records': 'டாக்டர் பதிவுகள்',
  'Add Cow': 'மாடு சேர்',
  'Add Calf': 'கன்று சேர்',
  'Edit Cow': 'மாட்டை மாற்று',
  'Edit Calf': 'கன்றை மாற்று',
  'Save Cow': 'மாட்டை சேமி',
  'Save Calf': 'கன்றை சேமி',
  'Save Changes': 'மாற்றத்தை சேமி',
  'Cow Name': 'மாட்டின் பெயர்',
  'Calf Name': 'கன்றின் பெயர்',
  'Cow': 'மாடு',
  'Calf': 'கன்று',
  'Mother Cow': 'தாய் மாடு',
  'Breed': 'இனம்',
  'Gender': 'பாலினம்',
  'Female': 'பெண்',
  'Male': 'ஆண்',
  'Date of Birth': 'பிறந்த தேதி',
  'Birth Date': 'பிறந்த தேதி',
  'Date': 'தேதி',
  'Time': 'நேரம்',
  'Age': 'வயது',
  'Source': 'எப்படி வந்தது',
  'Arrival Date': 'வருகை தேதி',
  'Purchase Amount': 'வாங்கிய தொகை',
  'Cow Photo': 'மாட்டின் படம்',
  'Calf Photo': 'கன்றின் படம்',
  'Choose Photo': 'படம் தேர்ந்தெடு',
  'Remove Photo': 'படத்தை நீக்கு',
  'Milk Quantity (Liter)': 'பால் அளவு (லிட்டர்)',
  'Morning': 'காலை',
  'Afternoon': 'மதியம்',
  'Evening': 'மாலை',
  'Quantity': 'அளவு',
  'Amount': 'தொகை',
  'Cost': 'செலவு',
  'Price': 'விலை',
  'Expense Name': 'செலவின் பெயர்',
  'Notes (optional)': 'குறிப்பு',
  'Doctor Visit': 'டாக்டர் பதிவு',
  'Treatment': 'சிகிச்சை',
  'Problem / Treatment': 'பிரச்சனை / சிகிச்சை',
  'Pregnancy': 'சினை',
  'Problem': 'பிரச்சனை',
  'Medicine': 'மருந்து',
  'Save Entry': 'பதிவை சேமி',
  'Save Sale': 'விற்றதை சேமி',
  'Customer Name': 'வாங்குபவர் பெயர்',
  'Milk Sale': 'பால் விற்பனை',
  'Manure': 'சாணம்',
  'Milk Details': 'பால் விவரங்கள்',
  'Expense Details': 'செலவு விவரங்கள்',
  'Farm Name': 'பண்ணையின் பெயர்',
  'Owner Name': 'உரிமையாளர் பெயர்',
  'Place': 'இடம்',
  'Currency Symbol': 'பண குறி',
  'Save Settings': 'செட்டிங்ஸை சேமி',
  'Default Milk Price per Liter': 'ஒரு லிட்டர் பால் விலை',
  'Ranch ID (permanent)': 'ராஞ்ச் ID (மாறாது)',
  'Ranch ID': 'ராஞ்ச் ID',
  'Admin': 'அட்மின்',
  'Editor': 'எடிட்டர்',
  'Data Entry': 'பதிவு போடுபவர்',
  'Active': 'செயலில்',
  'Sold': 'விற்கப்பட்டது',
  'Died': 'இறந்தது',
  'Pregnant': 'சினை',
  'Dry': 'கறவை நிறுத்தம்',
  'Existing': 'ஏற்கெனவே உள்ளது',
  'Born': 'பிறந்தது',
  'Purchased': 'வாங்கப்பட்டது',
  'Pending': 'காத்திருக்கிறது',
  'Accept': 'சேர்த்துக்கொள்',
  'Reject': 'வேண்டாம்',
  'Later': 'பிறகு',
  'Remove': 'நீக்கு',
  'Confirm': 'சரி',
  'Choose file': 'ஃபைலை தேர்வு செய்',
  'Email': 'இமெயில்',
  'Password': 'பாஸ்வேர்டு',
  'Sign In': 'லாகின்',
  'Create Account': 'புது அக்கவுண்ட்',
  'Forgot Password?': 'பாஸ்வேர்டு மறந்துடுச்சா?',
};

/// A label widget, retaining const call sites and native text scaling.
class AppText extends Text {
  const AppText(
    super.data, {
    super.key,
    super.style,
    super.textAlign,
    super.maxLines,
    super.overflow,
    super.softWrap,
    super.textDirection,
    super.semanticsLabel,
  });
  @override
  Widget build(BuildContext context) {
    // Subscribe to locale so already-open routes update with the preference.
    Localizations.localeOf(context);
    if (!tamilUi || data == null) return super.build(context);
    return Text(
      ui(data!),
      style: style?.copyWith(
        height: math.max(style?.height ?? 1.4, 1.4),
        letterSpacing: 0,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textDirection: textDirection,
      semanticsLabel: semanticsLabel,
    );
  }
}

const _surface = Color(0xFFF5F5F7);
const _blue = Ink.violetDeep;

Future<void> showEntryActions(BuildContext context) async {
  await push(context, const AddEntryScreen());
}

class _InsetGroup extends StatelessWidget {
  final List<Widget> children;
  const _InsetGroup({required this.children});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: Material(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: .5,
                indent: 54,
                color: Color(0xFFE5E5EA),
              ),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 60,
    leading: Icon(icon, color: _blue, size: 24),
    title: AppText(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
    trailing: const Icon(
      CupertinoIcons.chevron_forward,
      size: 15,
      color: Colors.grey,
    ),
    onTap: onTap,
  );
}

class TaskComposerScreen extends StatefulWidget {
  const TaskComposerScreen({super.key});
  @override
  State<TaskComposerScreen> createState() => _TaskComposerScreenState();
}

class _TaskComposerScreenState extends State<TaskComposerScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final Future<List<String>> _members = _loadMembers();
  String? _assignee;
  DateTime _due = DateTime.now();
  TimeOfDay _dueTime = const TimeOfDay(hour: 18, minute: 0);
  bool _saving = false;
  Future<List<String>> _loadMembers() async {
    final people = CloudSyncService.ready
        ? (await RanchAccessService.ranchRef(
                ranchId(),
              ).collection('members').get()).docs
              .map((d) => d.data())
              .where(
                (d) => d['active'] != false && txt(d, 'status') == 'active',
              )
              .toList()
        : deduplicateFamilyUsers(
            Hive.box('family_users').values.whereType<Map>(),
          );
    return {
      currentUserName(),
      ...people.map((p) => txt(p, 'name')),
    }.where((n) => n.isNotEmpty).toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final id = 'task_${DateTime.now().microsecondsSinceEpoch}';
      final now = DateTime.now().toIso8601String();
      final assignee = _assignee ?? currentUserName();
      await Hive.box('ranch_tasks').add({
        'taskId': id,
        'title': _title.text.trim(),
        'note': _note.text.trim(),
        'assignee': assignee,
        'assignedBy': currentUserName(),
        'dueDate': '${_due.year}-${two(_due.month)}-${two(_due.day)}',
        'dueTime': '${two(_dueTime.hour)}:${two(_dueTime.minute)}',
        'completed': false,
        'createdAt': now,
        'date': todayDate(),
        'time': currentTime(),
      });
      await Hive.box('ranch_messages').add({
        'text': _title.text.trim(),
        'sender': currentUserName(),
        'taskId': id,
        'eventType': 'assigned',
        'date': todayDate(),
        'time': currentTime(),
        'createdAt': now,
      });
      AutoSyncService.scheduleSync(reason: 'new task');
      unawaited(
        addRanchNotification(
          title: 'New task assigned',
          message: '${_title.text.trim()} • ${currentUserName()}',
          type: 'task',
          targetUser: assignee,
          sourceId: id,
        ).catchError((Object _) {}),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _surface,
    appBar: AppBar(
      leading: const _BackButton(),
      title: const AppText('New task'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: FutureBuilder<List<String>>(
            future: _members,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: AppText('Unable to load members'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CupertinoActivityIndicator());
              }
              final names = snapshot.data!;
              return Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _InsetGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextFormField(
                            controller: _title,
                            maxLength: 160,
                            minLines: 1,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: ui('Task'),
                              border: InputBorder.none,
                              counterText: '',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? ui('Task title is required')
                                : null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: TextField(
                            controller: _note,
                            maxLines: 4,
                            minLines: 2,
                            maxLength: 1000,
                            decoration: InputDecoration(
                              hintText: ui('Note'),
                              border: InputBorder.none,
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _InsetGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: DropdownButtonFormField<String>(
                            initialValue: names.contains(currentUserName())
                                ? currentUserName()
                                : names.firstOrNull,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: ui('Assign to'),
                              border: InputBorder.none,
                            ),
                            items: [
                              for (final name in names)
                                DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                            ],
                            validator: (v) =>
                                v == null ? ui('Assign to') : null,
                            onChanged: _saving ? null : (v) => _assignee = v,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(
                            CupertinoIcons.calendar,
                            color: _blue,
                            size: 24,
                          ),
                          title: const AppText('Due date'),
                          trailing: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_due),
                          ),
                          onTap: _saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _due,
                                    firstDate: DateTime.now().subtract(
                                      const Duration(days: 1),
                                    ),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => _due = picked);
                                  }
                                },
                        ),
                        ListTile(
                          leading: const Icon(
                            CupertinoIcons.clock,
                            color: _blue,
                            size: 24,
                          ),
                          title: const AppText('Target time'),
                          trailing: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatTimeOfDay(_dueTime),
                          ),
                          onTap: _saving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _dueTime,
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => _dueTime = picked);
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const CupertinoActivityIndicator()
                            : const AppText('Assign'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ConversationView extends StatefulWidget {
  final TextEditingController message;
  final Future<void> Function() onSend;
  final Future<void> Function(dynamic, Map<String, dynamic>) onToggle;
  final Future<void> Function(dynamic, Map<String, dynamic>) onDelete;
  final Future<void> Function(Uint8List, int) onSendVoice;
  const _ConversationView({
    required this.message,
    required this.onSend,
    required this.onToggle,
    required this.onDelete,
    required this.onSendVoice,
  });
  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
  static const int _voiceSampleRate = 8000;
  static const int _maxVoiceSeconds = 35;
  int _section = 0;
  bool _sending = false;
  bool _recording = false;
  bool _sendingVoice = false;
  int _recordingSeconds = 0;
  final _pendingTasks = <dynamic>{};
  final _pendingMessages = <dynamic>{};
  final AudioRecorder _recorder = AudioRecorder();
  BytesBuilder _recordedAudio = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _audioComplete;
  Timer? _recordingTimer;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    final subscription = _audioSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_recorder.cancel().catchError((Object _) {}));
    unawaited(_recorder.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording || _sendingVoice || _sending) return;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) snack(context, ui('Microphone permission is needed'));
        return;
      }
      _recordedAudio = BytesBuilder(copy: false);
      final complete = Completer<void>();
      _audioComplete = complete;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _voiceSampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSubscription = stream.listen(
        _recordedAudio.add,
        onDone: () {
          if (!complete.isCompleted) complete.complete();
        },
        onError: (Object error) {
          if (!complete.isCompleted) complete.completeError(error);
        },
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= _maxVoiceSeconds) {
          unawaited(_finishVoiceRecording());
        }
      });
    } catch (_) {
      if (mounted) snack(context, ui('Unable to record. Try again.'));
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    if (mounted) setState(() => _recording = false);
    try {
      await _recorder.cancel();
    } catch (_) {}
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _audioComplete = null;
    _recordedAudio = BytesBuilder(copy: false);
  }

  Future<void> _finishVoiceRecording() async {
    if (!_recording || _sendingVoice) return;
    _recordingTimer?.cancel();
    setState(() {
      _recording = false;
      _sendingVoice = true;
    });
    try {
      final duration = math.max(1, _recordingSeconds);
      final complete = _audioComplete;
      await _recorder.stop();
      if (complete != null) {
        await complete.future.timeout(const Duration(seconds: 3));
      }
      await _audioSubscription?.cancel();
      final pcm = _recordedAudio.takeBytes();
      if (pcm.isEmpty) throw StateError('No audio was recorded');
      await widget.onSendVoice(
        pcm16ToWave(pcm, sampleRate: _voiceSampleRate),
        duration,
      );
    } catch (error) {
      if (mounted) {
        final errorText = '$error';
        final message = errorText.contains('internet connection')
            ? 'Voice messages need an internet connection'
            : errorText.contains('too long')
            ? 'Voice message is too long'
            : 'Unable to record. Try again.';
        snack(context, ui(message));
      }
    } finally {
      _audioSubscription = null;
      _audioComplete = null;
      _recordedAudio = BytesBuilder(copy: false);
      if (mounted) setState(() => _sendingVoice = false);
    }
  }

  Future<void> _send() async {
    if (_sending || widget.message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend();
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> task) async {
    final key = task['_key'];
    if (_pendingTasks.contains(key)) return;
    setState(() => _pendingTasks.add(key));
    try {
      await widget.onToggle(key, task);
    } catch (_) {
      if (mounted) snack(context, ui('Unable to save. Try again.'));
    } finally {
      if (mounted) setState(() => _pendingTasks.remove(key));
    }
  }

  Future<void> _delete(Map<String, dynamic> message) async {
    if (!canManageRanch) return;
    final key = message['_key'];
    if (key == null || _pendingMessages.contains(key)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const SquircleBorder(radius: Gold.r27),
        title: const AppText(
          'Delete this message?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const AppText(
          'This removes the message for everyone in the ranch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText(
              'Delete',
              style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingMessages.add(key));
    try {
      await widget.onDelete(key, message);
      if (mounted) snack(context, ui('Message deleted'));
    } catch (_) {
      if (mounted) snack(context, ui('Unable to delete. Try again.'));
    } finally {
      if (mounted) setState(() => _pendingMessages.remove(key));
    }
  }

  Widget _messageWithAdminAction(Map<String, dynamic> message, Widget child) {
    if (!canManageRanch) return child;
    final key = message['_key'];
    final pending = _pendingMessages.contains(key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: pending ? null : () => _delete(message),
      child: AnimatedOpacity(
        opacity: pending ? .45 : 1,
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    );
  }

  Widget _chatBubble(Map<String, dynamic> message, bool mine) {
    final sender = txt(message, 'sender', 'Ranch member');
    final participantColor = chatParticipantColor(sender);
    final bubbleColor = Color.lerp(
      Colors.white,
      participantColor,
      mine ? .18 : .10,
    )!;
    final isVoice =
        txt(message, 'messageType') == 'voice' &&
        (txt(message, 'audioData').isNotEmpty ||
            txt(message, 'audioUrl').isNotEmpty);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: math.min(420, MediaQuery.sizeOf(context).width * .82),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
        decoration: BoxDecoration(
          color: bubbleColor,
          border: Border.all(
            color: participantColor.withValues(alpha: .18),
            width: .7,
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? 18 : 5),
            topRight: Radius.circular(mine ? 5 : 18),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: participantColor,
              ),
            ),
            const SizedBox(height: 4),
            if (isVoice)
              _VoiceMessageBubble(
                url: txt(message, 'audioUrl'),
                encodedAudio: txt(message, 'audioData'),
                durationSeconds: toInt(message['audioDuration']),
                color: participantColor,
              )
            else
              Text(
                txt(message, 'text'),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Ink.navy,
                ),
              ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                txt(message, 'time'),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: participantColor.withValues(alpha: .72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task, {String sender = ''}) {
    final done = task['completed'] == true;
    final canComplete =
        txt(task, 'assignee') == currentUserName() || canManageRanch;
    final assignee = txt(task, 'assignee');
    final assigneeColor = chatParticipantColor(assignee);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA), width: .5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: ui(done ? 'Completed' : 'Open'),
              onPressed: canComplete && !_pendingTasks.contains(task['_key'])
                  ? () => _toggle(task)
                  : null,
              icon: Icon(
                done
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: done
                    ? const Color(0xFF34C759)
                    : canComplete
                    ? _blue
                    : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sender.isNotEmpty) ...[
                  Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: chatParticipantColor(sender),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  txt(task, 'title'),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? Ink.muted : Ink.navy,
                  ),
                ),
                if (txt(task, 'note').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    txt(task, 'note'),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Ink.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: assigneeColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: assigneeColor.withValues(alpha: .24),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.person_fill,
                            size: 13,
                            color: assigneeColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            assignee,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: assigneeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppText(
                      done ? 'Completed' : 'Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: done ? Ink.green : _blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      Hive.box('ranch_messages').listenable(),
      Hive.box('ranch_tasks').listenable(),
    ]),
    builder: (context, _) {
      final messages =
          Hive.box('ranch_messages')
              .toMap()
              .entries
              .where((entry) => entry.value is Map)
              .map((entry) => {...asMap(entry.value), '_key': entry.key})
              .toList()
            ..sort(
              (a, b) => txt(b, 'createdAt').compareTo(txt(a, 'createdAt')),
            );
      final tasks =
          Hive.box('ranch_tasks')
              .toMap()
              .entries
              .map((e) => {...asMap(e.value), '_key': e.key})
              .toList()
            ..sort((a, b) {
              if ((a['completed'] == true) != (b['completed'] == true)) {
                return a['completed'] == true ? 1 : -1;
              }
              return txt(b, 'createdAt').compareTo(txt(a, 'createdAt'));
            });
      final byId = {for (final t in tasks) txt(t, 'taskId'): t};
      return ColoredBox(
        color: _surface,
        child: Shell(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9E9EE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: CupertinoSlidingSegmentedControl<int>(
                            groupValue: _section,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.transparent,
                            thumbColor: Colors.white,
                            children: const {
                              0: Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: AppText('Messages'),
                              ),
                              1: Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: AppText('Tasks'),
                              ),
                            },
                            onValueChanged: (v) {
                              if (v != null) setState(() => _section = v);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: ui('New task'),
                      onPressed: () =>
                          push(context, const TaskComposerScreen()),
                      icon: const Icon(
                        CupertinoIcons.square_pencil,
                        color: _blue,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _section == 1
                    ? tasks.isEmpty
                          ? const Center(
                              child: AppText(
                                'No tasks',
                                style: TextStyle(color: Ink.muted),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: tasks.length,
                              itemBuilder: (_, i) => _taskCard(
                                tasks[i],
                                sender: txt(tasks[i], 'assignedBy'),
                              ),
                            )
                    : messages.isEmpty
                    ? const Center(
                        child: AppText(
                          'No messages',
                          style: TextStyle(color: Ink.muted),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[i];
                          final mine = txt(m, 'sender') == currentUserName();
                          final task = byId[txt(m, 'taskId')];
                          final showTaskCard = taskMessageShowsCard(m, task);
                          final showDate =
                              i == messages.length - 1 ||
                              txt(messages[i + 1], 'date') != txt(m, 'date');
                          return Column(
                            children: [
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xEFFFFFFF),
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x12000000),
                                          blurRadius: 5,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: AppText(
                                      chatDateLabel(txt(m, 'date')),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Ink.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              if (showTaskCard)
                                _messageWithAdminAction(
                                  m,
                                  _taskCard(task!, sender: txt(m, 'sender')),
                                )
                              else
                                _messageWithAdminAction(
                                  m,
                                  _chatBubble(m, mine),
                                ),
                            ],
                          );
                        },
                      ),
              ),
              if (_section == 0)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: const Color(0xFFD1D1D6),
                          width: .7,
                        ),
                      ),
                      child: _recording || _sendingVoice
                          ? Row(
                              children: [
                                IconButton(
                                  tooltip: ui('Cancel recording'),
                                  onPressed: _sendingVoice
                                      ? null
                                      : _cancelVoiceRecording,
                                  icon: const Icon(
                                    CupertinoIcons.delete,
                                    color: Ink.red,
                                  ),
                                ),
                                Expanded(
                                  child: _sendingVoice
                                      ? const Center(
                                          child: CupertinoActivityIndicator(),
                                        )
                                      : Row(
                                          children: [
                                            const Icon(
                                              Icons.fiber_manual_record,
                                              size: 13,
                                              color: Ink.red,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              voiceDurationLabel(
                                                _recordingSeconds,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: Ink.navy,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: AppText(
                                                'Voice message',
                                                style: TextStyle(
                                                  color: Ink.muted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                                IconButton(
                                  tooltip: ui('Send voice message'),
                                  onPressed: _sendingVoice
                                      ? null
                                      : _finishVoiceRecording,
                                  icon: const Icon(
                                    CupertinoIcons.arrow_up_circle_fill,
                                    size: 34,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: widget.message,
                                    minLines: 1,
                                    maxLines: 5,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    textInputAction: TextInputAction.newline,
                                    decoration: InputDecoration(
                                      hintText: ui('Message'),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: widget.message,
                                  builder: (_, v, _) {
                                    final hasText = v.text.trim().isNotEmpty;
                                    return IconButton(
                                      tooltip: ui(
                                        hasText
                                            ? 'Send'
                                            : 'Record voice message',
                                      ),
                                      onPressed: _sending
                                          ? null
                                          : hasText
                                          ? _send
                                          : _startRecording,
                                      icon: _sending
                                          ? const CupertinoActivityIndicator()
                                          : Icon(
                                              hasText
                                                  ? CupertinoIcons
                                                        .arrow_up_circle_fill
                                                  : CupertinoIcons
                                                        .mic_circle_fill,
                                              size: 34,
                                              color: _blue,
                                            ),
                                    );
                                  },
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
    },
  );
}

class _VoiceMessageBubble extends StatefulWidget {
  final String url;
  final String encodedAudio;
  final int durationSeconds;
  final Color color;
  const _VoiceMessageBubble({
    required this.url,
    required this.encodedAudio,
    required this.durationSeconds,
    required this.color,
  });

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSeconds);
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSubscription = _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _stateSubscription = _player.onPlayerStateChanged.listen((value) {
      if (mounted) setState(() => _state = value);
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _state = PlayerState.stopped;
        });
      }
    });
  }

  @override
  void dispose() {
    final positionSubscription = _positionSubscription;
    final durationSubscription = _durationSubscription;
    final stateSubscription = _stateSubscription;
    final completeSubscription = _completeSubscription;
    if (positionSubscription != null) unawaited(positionSubscription.cancel());
    if (durationSubscription != null) unawaited(durationSubscription.cancel());
    if (stateSubscription != null) unawaited(stateSubscription.cancel());
    if (completeSubscription != null) unawaited(completeSubscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      final source = widget.encodedAudio.isNotEmpty
          ? BytesSource(base64Decode(widget.encodedAudio))
          : UrlSource(widget.url);
      await _player.play(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = math.max(1, _duration.inMilliseconds);
    final positionMs = math.min(_position.inMilliseconds, durationMs);
    final shownSeconds = _state == PlayerState.playing
        ? _position.inSeconds
        : math.max(widget.durationSeconds, _duration.inSeconds);
    return SizedBox(
      width: math.min(280, MediaQuery.sizeOf(context).width * .64),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: _state == PlayerState.playing ? 'Pause' : 'Play',
            style: IconButton.styleFrom(
              backgroundColor: widget.color.withValues(alpha: .14),
              foregroundColor: widget.color,
            ),
            onPressed: _togglePlayback,
            icon: Icon(
              _state == PlayerState.playing
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              size: 20,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: widget.color,
                inactiveTrackColor: widget.color.withValues(alpha: .2),
                thumbColor: widget.color,
                overlayColor: widget.color.withValues(alpha: .1),
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: positionMs.toDouble(),
                max: durationMs.toDouble(),
                onChanged: (value) =>
                    _player.seek(Duration(milliseconds: value.round())),
              ),
            ),
          ),
          Text(
            voiceDurationLabel(shownSeconds),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

const _helpEntries = <(String, String, String)>[
  (
    'Dashboard',
    'The dashboard shows today’s milk, animals, expenses, sales and the latest ranch activity.',
    'Dashboard-ல இன்றைய பால், மாடுகள், செலவு, விற்பனை, கடைசி பதிவுகள் எல்லாம் ஒரே இடத்தில் தெரியும்.',
  ),
  (
    'Cows & Calves',
    'Add cows and calves, open a profile, and review milk, health and timeline records.',
    'மாடு, கன்றை சேர்க்கலாம். Profile-ஐ திறந்தா பால், டாக்டர் பதிவு, முழு timeline எல்லாம் பார்க்கலாம்.',
  ),
  (
    'Entry actions',
    'Use + to add milk, stock use or an expense. On Recent Activity, use the three-dot menu to edit your entry for five minutes or add a note.',
    '+ பட்டனை தொட்டு பால், தீவனம் அல்லது செலவு பதிவு போடலாம். Recent Activity-ல மூன்று புள்ளியை தொட்டா 5 நிமிஷத்துக்குள் edit பண்ணலாம்; note-ம் சேர்க்கலாம்.',
  ),
  (
    'Chat',
    'Share messages with your ranch. Swipe inward from the right edge to open Chat. Swipe inward from the left edge to open Settings.',
    'ராஞ்ச் ஆட்களுக்கு இங்கே message அனுப்பலாம். வலது ஓரத்திலிருந்து உள்ளே swipe பண்ணா Chat; இடது ஓரத்திலிருந்து swipe பண்ணா Settings திறக்கும்.',
  ),
  (
    'Tasks',
    'Create a task with a member, due date and target time. The assignee or an admin can mark it complete.',
    'யாருக்கு வேலை கொடுக்கணுமோ அவரை தேர்வு பண்ணி, முடிக்க வேண்டிய நாள் மற்றும் நேரம் போடலாம். அவர் அல்லது Admin முடிச்சதா mark பண்ணலாம்.',
  ),
  (
    'Timeline',
    'Open a cow profile to see dated birth, pregnancy, treatment, calving, milk and linked financial records. Shared ranch expenses are not assigned to an individual cow.',
    'மாட்டோட profile-ல பிறந்த நாள், சினை, doctor, கன்று பிறப்பு, பால், பணப்பதிவு எல்லாம் date-ோடு பார்க்கலாம். பொதுச் செலவு தனி மாட்டில் வராது.',
  ),
  (
    'Notifications',
    'The bell opens notification history. Tap an item to mark it read. Daily reminders currently require the app to be active at the reminder time.',
    'Bell பட்டனை தொட்டா notification history வரும். ஒன்றை தொட்டா பார்த்ததாக mark ஆகும். தினசரி reminder வர அந்த நேரத்தில் app open-ஆ இருக்கணும்.',
  ),
  (
    'Family Users',
    'Members join using your permanent Ranch ID. An admin approves requests and controls member roles. Role restrictions still apply in every language.',
    'உங்களோட Ranch ID வைத்து வீட்டு ஆட்கள் join பண்ணலாம். Admin request-ஐ accept பண்ணி யாருக்கு என்ன accessன்னு தேர்வு பண்ணலாம்.',
  ),
  (
    'Cloud Sync',
    'Records are saved on this device first and sync to your ranch account. Manual upload and download are available in Cloud Sync.',
    'பதிவு முதலில் இந்த phone-ல save ஆகும்; அப்புறம் ranch account-க்கு sync ஆகும். Cloud Sync-ல upload அல்லது download பண்ணலாம்.',
  ),
  (
    'Export and Backup',
    'Export the complete Excel workbook or individual CSV reports. Full Backup saves a restorable JSON file. Restore Backup replaces this device’s data with the selected backup.',
    'முழு Excel file அல்லது தனித்தனி CSV report download பண்ணலாம். Full Backup எடுத்தா பிறகு அதே data-வை திரும்ப restore பண்ணலாம்.',
  ),
  (
    'Calf Born',
    'Register a calf from a pregnant female’s profile. First calving moves a heifer to Cows and starts her lactation.',
    'சினை மாட்டோட profile-ல இருந்து கன்று பிறந்ததை பதிவு பண்ணலாம். முதல் கன்று பிறந்ததும் கிடேரி தானாக மாடு list-க்கு மாறும்.',
  ),
  (
    'Stock',
    'Stock purchases increase the balance. Daily use reduces it. Straw is recorded in bundles; bran in kilograms.',
    'தீவனம் வாங்கினா stock கூடும்; தினமும் எடுத்ததை போட்டா stock குறையும். வைக்கோல் கட்டிலும், தவிடு kg-லவும் பதிவு ஆகும்.',
  ),
  (
    'Sell',
    'Record milk, cow, calf and manure sales. New sales automatically use the current date and time.',
    'பால், மாடு, கன்று, சாணம் விற்றதை இங்கே பதிவு பண்ணலாம். Date, time தானாகவே இப்போதைய நேரத்துக்கு save ஆகும்.',
  ),
  (
    'Reports',
    'Daily, monthly and overall reports combine milk, expenses and sales. Export them from Settings.',
    'Daily, monthly, full report-ல பால், செலவு, விற்பனை எல்லாம் வரும். Settings-ல இருந்து file-ஆ download பண்ணலாம்.',
  ),
  (
    'App Settings',
    'Set the farm name, owner, place, currency and default milk price. Ranch ID stays permanent.',
    'பண்ணை பெயர், owner பெயர், இடம், பண குறி, வழக்கமான பால் விலை எல்லாம் இங்கே மாற்றலாம். Ranch ID மட்டும் மாறாது.',
  ),
];

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _surface,
    appBar: AppBar(title: const AppText('Info'), leading: const _BackButton()),
    body: Shell(
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _helpEntries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, i) {
          final entry = _helpEntries[i];
          return _InsetGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      entry.$1,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tamilUi ? entry.$3 : entry.$2,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Ink.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
