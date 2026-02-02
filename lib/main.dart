import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

void main() => runApp(const HealthTrackerApp());

class HealthTrackerApp extends StatelessWidget {
  const HealthTrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(),
    home: const HealthTracker(),
  );
}

class HealthTracker extends StatefulWidget {
  const HealthTracker({super.key});

  @override
  State<HealthTracker> createState() => _HealthTrackerState();
}

class _HealthTrackerState extends State<HealthTracker> {
  late Icarus _icarus;
  late DateTime _currentDate;
  double? _height, _weight;
  DateTime? _lastWeightUpdate;
  bool _showInputOverlay = false;
  String _currentInputType = '';
  final TextEditingController _inputController = TextEditingController();
  
  List<String> _selectedLogTypes = ['weight'];
  Map<DateTime, Map<String, dynamic>> _logEntriesByDate = {};
  Map<String, Color> _typeColors = {'weight': Colors.orange, 'protein': Colors.purple};
  DateTime? _selectedLogDate;
  String? _selectedLogType;
  dynamic _selectedLogValue;

  List<String> _events = [];
  Map<String, List<DateTime>> _activityDates = {};

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime.now();
    _icarus = Icarus(date: _currentDate);
    _loadInitialData();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    _height = await Storage.loadHeight();
    _events = await Storage.loadEvents();
    final entries = await Storage.loadLogEntries();
    await _loadActivityDates();
    
    final weightEntries = entries.where((e) => e.type == 'W');
    if (weightEntries.isNotEmpty) {
      final latest = weightEntries.last;
      _weight = latest.quantity;
      _lastWeightUpdate = latest.date;
    }
    
    _updateLogEntriesMap();
  }

  Future<void> _loadActivityDates() async {
    final activities = await Storage.loadActivities();
    _activityDates.clear();
    
    for (var activity in activities) {
      final date = DateTime(activity.date.year, activity.date.month, activity.date.day);
      _activityDates.putIfAbsent(activity.activity, () => []).add(date);
    }
  }

  void _updateLogEntriesMap() {
    Storage.loadLogEntries().then((entries) async {
      await _loadActivityDates();
      
      setState(() {
        _logEntriesByDate.clear();
        
        for (var entry in entries) {
          final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
          _logEntriesByDate.putIfAbsent(date, () => {});
          final type = entry.type == 'W' ? 'weight' : 'protein';
          _logEntriesByDate[date]![type] = entry.quantity;
        }
        
        for (var activity in _activityDates.keys) {
          for (var date in _activityDates[activity]!) {
            _logEntriesByDate.putIfAbsent(date, () => {})[activity] = true;
          }
        }
      });
    });
  }

  Future<void> _handleSave() async {
    if (_currentInputType == 'event') {
      final eventName = _inputController.text.trim();
      if (eventName.isEmpty) return _showError();
      
      await Storage.addEvent(eventName);
      await _loadInitialData();
      setState(() => _showInputOverlay = false);
      return;
    }

    final input = double.tryParse(_inputController.text);
    if (input == null || input <= 0) return _showError();

    if (_currentInputType == 'height' && input <= 300) {
      await Storage.saveHeight(input);
      setState(() => _height = input);
    } 
    else if (_currentInputType == 'weight' && input <= 500) {
      final now = DateTime.now();
      await Storage.saveLogEntry('W', input, now);
      setState(() {
        _weight = input;
        _lastWeightUpdate = now;
      });
      _updateLogEntriesMap();
    }
    else if (_currentInputType == 'protein' && input <= 500) {
      await Storage.saveLogEntry('P', input, DateTime.now());
      _updateLogEntriesMap();
    } else {
      return _showError();
    }

    setState(() => _showInputOverlay = false);
  }

  Future<void> _logActivityToToday(String activity) async {
    final today = DateTime.now();
    await Storage.saveActivity(activity, today);
    await _loadActivityDates();
    _updateLogEntriesMap();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged "$activity" for today')),
    );
  }

  void _showActivitySelectionDialog() {
    if (_events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No events created yet')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Activity for Today'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _events.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(_events[index]),
              onTap: () {
                Navigator.pop(context);
                _logActivityToToday(_events[index]);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showError() {
    final message = _currentInputType == 'height' ? 'Enter valid height (1-300 cm)'
                 : _currentInputType == 'weight' ? 'Enter valid weight (1-500 kg)'
                 : _currentInputType == 'protein' ? 'Enter valid protein (1-500 g)'
                 : 'Enter event name';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showInputDialog(String type) {
    setState(() {
      _currentInputType = type;
      _showInputOverlay = true;
      _inputController.text = type == 'height' ? _height?.toStringAsFixed(1) ?? ''
                          : type == 'weight' ? _weight?.toStringAsFixed(1) ?? ''
                          : type == 'event' ? ''
                          : '';
    });
  }

  Future<void> _deleteEvent(String eventName) async {
    await Storage.removeEvent(eventName);
    await _loadInitialData();
    setState(() {});
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Event "$eventName" deleted')),
    );
  }

  void _showDeleteEventDialog() {
    if (_events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No events to delete')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _events.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(_events[index]),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  Navigator.pop(context);
                  _deleteEvent(_events[index]);
                },
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _cancelInput() {
    setState(() {
      _showInputOverlay = false;
      _selectedLogDate = null;
      _selectedLogType = null;
      _selectedLogValue = null;
    });
    _inputController.clear();
  }

  double? get _bmi => _weight != null && _height != null 
    ? _weight! / ((_height! / 100) * (_height! / 100)) 
    : null;

  String? get _bmiCategory => _bmi == null ? null
    : _bmi! < 18.5 ? 'Underweight'
    : _bmi! < 25 ? 'Normal'
    : _bmi! < 30 ? 'Overweight'
    : 'Obese';

  Color? get _bmiColor => _bmi == null ? null
    : _bmi! < 18.5 ? Colors.blue
    : _bmi! < 25 ? Colors.green
    : _bmi! < 30 ? Colors.orange
    : Colors.red;

  void _previousMonth() {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month - 1);
      _icarus = Icarus(date: _currentDate);
      _selectedLogDate = null;
      _selectedLogType = null;
      _selectedLogValue = null;
    });
  }

  void _nextMonth() {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month + 1);
      _icarus = Icarus(date: _currentDate);
      _selectedLogDate = null;
      _selectedLogType = null;
      _selectedLogValue = null;
    });
  }

  void _showActionMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ActionMenu(
        onSelect: _showInputDialog,
        onDeleteEvent: _showDeleteEventDialog,
      ),
    );
  }

  void _toggleLogType(String type, bool? value) {
    setState(() {
      if (value == true) {
        _selectedLogTypes.add(type);
      } else {
        _selectedLogTypes.remove(type);
      }
      _selectedLogDate = null;
      _selectedLogType = null;
      _selectedLogValue = null;
    });
    _updateLogEntriesMap();
  }

  void _onDayClicked(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    if (_logEntriesByDate.containsKey(normalizedDay)) {
      final entries = _logEntriesByDate[normalizedDay]!;
      final selectedTypes = _selectedLogTypes.where((type) => entries.containsKey(type)).toList();
      
      if (selectedTypes.isNotEmpty) {
        setState(() {
          _selectedLogDate = normalizedDay;
          _selectedLogType = selectedTypes.first;
          _selectedLogValue = entries[selectedTypes.first];
        });
      } else {
        setState(() {
          _selectedLogDate = null;
          _selectedLogType = null;
          _selectedLogValue = null;
        });
      }
    } else {
      setState(() {
        _selectedLogDate = null;
        _selectedLogType = null;
        _selectedLogValue = null;
      });
    }
  }

  Color _getTypeColor(String type) {
    if (!_typeColors.containsKey(type)) {
      _typeColors[type] = Colors.primaries[type.hashCode.abs() % Colors.primaries.length];
    }
    return _typeColors[type]!;
  }

  List<Color> _getDayColors(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final isToday = day.isSameDay(DateTime.now());
    final isSelected = _selectedLogDate == normalizedDay;
    final colors = <Color>[];
    
    if (isToday) colors.add(Colors.blue.withOpacity(0.3));
    if (isSelected) colors.add(Colors.green.withOpacity(0.5));
    
    if (_logEntriesByDate.containsKey(normalizedDay)) {
      for (var type in _selectedLogTypes) {
        if (_logEntriesByDate[normalizedDay]!.containsKey(type)) {
          colors.add(_getTypeColor(type).withOpacity(0.4));
        }
      }
    }
    
    return colors;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: Stack(
        children: [
          Column(children: [
            _buildHealthCard(),
            _buildLogSelector(),
            _buildMonthNavigation(),
            _buildWeekdayHeaders(),
            Expanded(child: _buildCalendarWithSwipe()),
            _buildAddActivityButton(),
            _buildSelectedDayInfo(),
          ]),
          if (_showInputOverlay) _buildInputOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showActionMenu,
        child: const Icon(Icons.menu),
      ),
    );
  }

  Widget _buildHealthCard() => Card(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('BMI', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(_bmi != null ? _bmi!.toStringAsFixed(1) : '--', 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _bmiColor)),
            if (_bmiCategory != null) Text(_bmiCategory!, 
              style: TextStyle(fontSize: 12, color: _bmiColor)),
          ]),
          Column(children: [
            const Text('Weight', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(_weight != null ? '${_weight!.toStringAsFixed(1)} kg' : '-- kg', 
              style: const TextStyle(fontSize: 16)),
          ]),
          Column(children: [
            const Text('Height', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(_height != null ? '${_height!.toStringAsFixed(1)} cm' : '-- cm', 
              style: const TextStyle(fontSize: 16)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(
          _lastWeightUpdate != null 
            ? 'Last updated: ${DateFormat('MMM d, yyyy').format(_lastWeightUpdate!)}'
            : 'No weight logged yet',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ]),
    ),
  );

  Widget _buildLogSelector() {
    final allOptions = ['weight', 'protein', ..._events];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            'Selected: ${_selectedLogTypes.length} item${_selectedLogTypes.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 14),
          ),
          children: [
            SizedBox(
              height: 200,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allOptions.length,
                itemBuilder: (context, index) {
                  final option = allOptions[index];
                  return CheckboxListTile(
                    title: Row(children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _getTypeColor(option),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        option == 'weight' ? 'Weight Logs' 
                        : option == 'protein' ? 'Protein Logs' 
                        : option,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ]),
                    value: _selectedLogTypes.contains(option),
                    onChanged: (bool? value) => _toggleLogType(option, value),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthNavigation() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _previousMonth),
      Text(_icarus.monthName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
    ]),
  );

  Widget _buildWeekdayHeaders() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: 7,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(8),
        child: Text(
          _icarus.weekdays[index],
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
    ),
  );

  Widget _buildCalendarWithSwipe() => GestureDetector(
    onHorizontalDragEnd: (details) {
      if (details.primaryVelocity! > 0) _previousMonth();
      else if (details.primaryVelocity! < 0) _nextMonth();
    },
    child: _buildCalendarGrid(),
  );

  Widget _buildCalendarGrid() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: _icarus.calendarDays.length,
      itemBuilder: (context, index) => _buildCalendarCell(_icarus.calendarDays[index]),
    ),
  );

  Widget _buildCalendarCell(DateTime day) {
    final colors = _getDayColors(day);
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final isSelected = _selectedLogDate == normalizedDay;
    
    return GestureDetector(
      onTap: () => _onDayClicked(day),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.isEmpty ? Colors.transparent : _blendColors(colors),
            border: colors.isEmpty ? null : Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Center(child: Text(
            day.day.toString(),
            style: TextStyle(
              fontSize: 16,
              color: day.month == _icarus.currentMonth ? Colors.white : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          )),
        ),
      ),
    );
  }

  Color _blendColors(List<Color> colors) {
    if (colors.isEmpty) return Colors.transparent;
    if (colors.length == 1) return colors.first;
    
    double r = 0, g = 0, b = 0, a = 0;
    for (var color in colors) {
      r += color.red;
      g += color.green;
      b += color.blue;
      a += color.opacity;
    }
    
    return Color.fromRGBO(
      (r / colors.length).round(),
      (g / colors.length).round(),
      (b / colors.length).round(),
      (a / colors.length).clamp(0.0, 1.0),
    );
  }

  Widget _buildAddActivityButton() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showActivitySelectionDialog,
        icon: const Icon(Icons.add_circle),
        label: const Text('Add Activity to Today'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: Colors.purple.withOpacity(0.8),
        ),
      ),
    ),
  );

  Widget _buildSelectedDayInfo() {
    if (_selectedLogDate == null || _selectedLogType == null || _selectedLogValue == null) {
      return const SizedBox(height: 20);
    }
    
    final displayText = _selectedLogType == 'weight' || _selectedLogType == 'protein'
      ? '${_selectedLogValue!.toStringAsFixed(1)} ${_selectedLogType == 'weight' ? 'kg' : 'g'}'
      : _selectedLogType!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        displayText,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Widget _buildInputOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(child: Card(
        margin: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _currentInputType == 'height' ? 'Enter Height' 
                : _currentInputType == 'weight' ? 'Enter Weight' 
                : _currentInputType == 'protein' ? 'Enter Protein'
                : 'Create Event',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _inputController,
              keyboardType: _currentInputType == 'event' ? TextInputType.text : TextInputType.number,
              decoration: InputDecoration(
                labelText: _currentInputType == 'height' ? 'Height' 
                  : _currentInputType == 'weight' ? 'Weight' 
                  : _currentInputType == 'protein' ? 'Protein'
                  : 'Event Name',
                border: const OutlineInputBorder(),
                suffixText: _currentInputType == 'height' ? 'cm' 
                  : _currentInputType == 'weight' ? 'kg' 
                  : _currentInputType == 'protein' ? 'g'
                  : '',
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton(onPressed: _cancelInput, child: const Text('Cancel')),
              ElevatedButton(onPressed: _handleSave, child: const Text('Save')),
            ]),
          ]),
        ),
      )),
    ),
  );
}

class ActionMenu extends StatelessWidget {
  final Function(String) onSelect;
  final VoidCallback onDeleteEvent;
  
  const ActionMenu({super.key, required this.onSelect, required this.onDeleteEvent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _buildButton(Icons.height, 'Set Height', 'height', context),
      const SizedBox(height: 10),
      _buildButton(Icons.monitor_weight, 'Log Weight', 'weight', context),
      const SizedBox(height: 10),
      _buildButton(Icons.fitness_center, 'Log Protein', 'protein', context),
      const SizedBox(height: 10),
      _buildButton(Icons.event, 'Create Event', 'event', context),
      const SizedBox(height: 10),
      _buildDeleteEventButton(context),
    ]),
  );

  Widget _buildButton(IconData icon, String label, String type, BuildContext context) => 
    ElevatedButton.icon(
      onPressed: () { Navigator.pop(context); onSelect(type); },
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
    );

  Widget _buildDeleteEventButton(BuildContext context) => ElevatedButton(
    onPressed: () { Navigator.pop(context); onDeleteEvent(); },
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 50),
      backgroundColor: Colors.red.withOpacity(0.2),
      foregroundColor: Colors.red,
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.delete, color: Colors.red),
      SizedBox(width: 8),
      Text('Delete Event', style: TextStyle(color: Colors.red)),
    ]),
  );
}

class Storage {
  static const String _logFile = 'icarus_log.csv';
  static const String _activityFile = 'icarus_activity.csv';
  static const String _jsonFile = 'icarus.json';

  static Future<File> _getFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$filename');
  }

  static Future<Map<String, dynamic>> _loadJson() async {
    try {
      final file = await _getFile(_jsonFile);
      if (!await file.exists()) return {'height': null, 'events': []};
      return jsonDecode(await file.readAsString());
    } catch (e) {
      return {'height': null, 'events': []};
    }
  }

  static Future<void> _saveJson(Map<String, dynamic> data) async {
    try {
      final file = await _getFile(_jsonFile);
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<double?> loadHeight() async {
    final json = await _loadJson();
    final height = json['height'];
    return height != null ? (height as num).toDouble() : null;
  }

  static Future<void> saveHeight(double height) async {
    final json = await _loadJson();
    json['height'] = height;
    await _saveJson(json);
  }

  static Future<List<String>> loadEvents() async {
    final json = await _loadJson();
    final events = json['events'];
    if (events is List) return List<String>.from(events);
    return [];
  }

  static Future<void> addEvent(String eventName) async {
    final json = await _loadJson();
    if (!json.containsKey('events') || json['events'] is! List) {
      json['events'] = [];
    }
    (json['events'] as List).add(eventName);
    await _saveJson(json);
  }

  static Future<void> removeEvent(String eventName) async {
    final json = await _loadJson();
    if (json.containsKey('events') && json['events'] is List) {
      final events = (json['events'] as List).cast<String>();
      events.removeWhere((event) => event == eventName);
      json['events'] = events;
      await _saveJson(json);
    }
  }

  static Future<void> saveActivity(String activity, DateTime date) async {
    final file = await _getFile(_activityFile);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final line = '$activity,$dateStr\n';
    
    if (await file.exists()) {
      await file.writeAsString(line, mode: FileMode.append);
    } else {
      await file.writeAsString('activity,date\n$line');
    }
  }

  static Future<List<ActivityEntry>> loadActivities() async {
    try {
      final file = await _getFile(_activityFile);
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final entries = <ActivityEntry>[];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length >= 2) {
          try {
            entries.add(ActivityEntry(
              activity: parts[0],
              date: DateFormat('yyyy-MM-dd').parse(parts[1]),
            ));
          } catch (_) {}
        }
      }

      entries.sort((a, b) => a.date.compareTo(b.date));
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLogEntry(String type, double quantity, DateTime date) async {
    final file = await _getFile(_logFile);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final line = '$type,$quantity,$dateStr\n';
    
    if (await file.exists()) {
      await file.writeAsString(line, mode: FileMode.append);
    } else {
      await file.writeAsString('Op,Quantity,Date\n$line');
    }
  }

  static Future<List<LogEntry>> loadLogEntries() async {
    try {
      final file = await _getFile(_logFile);
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final entries = <LogEntry>[];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length >= 3) {
          try {
            entries.add(LogEntry(
              type: parts[0],
              quantity: double.parse(parts[1]),
              date: DateFormat('yyyy-MM-dd').parse(parts[2]),
            ));
          } catch (_) {}
        }
      }

      entries.sort((a, b) => a.date.compareTo(b.date));
      return entries;
    } catch (_) {
      return [];
    }
  }
}

class LogEntry {
  final String type;
  final double quantity;
  final DateTime date;
  LogEntry({required this.type, required this.quantity, required this.date});
}

class ActivityEntry {
  final String activity;
  final DateTime date;
  ActivityEntry({required this.activity, required this.date});
}

class Icarus {
  final DateTime date;
  late final int currentMonth, currentYear;
  late final String monthName;
  final List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  late final List<DateTime> calendarDays;

  Icarus({required this.date}) {
    currentMonth = date.month;
    currentYear = date.year;
    monthName = _getMonthName(currentMonth);
    calendarDays = _generateCalendarDays();
  }

  String _getMonthName(int month) => const [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ][month - 1];

  List<DateTime> _generateCalendarDays() {
    final firstDay = DateTime(currentYear, currentMonth, 1);
    final lastDay = DateTime(currentYear, currentMonth + 1, 0);
    final startDate = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final endDate = lastDay.add(Duration(days: (6 - lastDay.weekday) % 7));
    
    final days = <DateTime>[];
    DateTime current = startDate;
    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }
}

extension DateTimeExtension on DateTime {
  bool isSameDay(DateTime other) => year == other.year && month == other.month && day == other.day;
}
