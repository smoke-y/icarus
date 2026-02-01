import 'dart:io';
import 'dart:math';
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
  
  String _selectedLogType = 'weight';
  Map<DateTime, double> _logEntriesByDate = {};
  DateTime? _selectedLogDate;
  double? _selectedLogValue;

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
    final entries = await Storage.loadLogEntries();
    
    final weightEntries = entries.where((e) => e.type == 'W');
    if (weightEntries.isNotEmpty) {
      final latest = weightEntries.last;
      _weight = latest.quantity;
      _lastWeightUpdate = latest.date;
    }
    
    _updateLogEntriesMap();
  }

  void _updateLogEntriesMap() {
    Storage.loadLogEntries().then((entries) {
      setState(() {
        _logEntriesByDate.clear();
        final typeChar = _selectedLogType == 'weight' ? 'W' : 'P';
        
        for (var entry in entries) {
          if (entry.type == typeChar) {
            final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
            _logEntriesByDate[date] = entry.quantity;
          }
        }
      });
    });
  }

  Future<void> _createTestData() async {
    final dir = await getApplicationDocumentsDirectory();
    final logFile = File('${dir.path}/icarus_log.csv');
    final jsonFile = File('${dir.path}/icarus.json');
    
    await jsonFile.writeAsString(jsonEncode({'height': 175.0}));
    
    final now = DateTime.now();
    final random = Random();
    final lines = <String>['Op,Quantity,Date'];
    
    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: 30 - i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      if (i % 2 == 0) {
        lines.add('W,${(70.0 + random.nextDouble() * 5.0).toStringAsFixed(1)},$dateStr');
      }
      if (i % 3 == 0) {
        lines.add('P,${(80.0 + random.nextDouble() * 40.0).toStringAsFixed(1)},$dateStr');
      }
    }
    
    for (final date in [now, now.subtract(const Duration(days: 1)), now.subtract(const Duration(days: 2))]) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      lines.add('W,${(72.0 + random.nextDouble() * 3.0).toStringAsFixed(1)},$dateStr');
      lines.add('P,${(90.0 + random.nextDouble() * 30.0).toStringAsFixed(1)},$dateStr');
    }
    
    await logFile.writeAsString(lines.join('\n'));
    await _loadInitialData();
    setState(() {});
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test data created!')),
    );
  }

  Future<void> _handleSave() async {
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

  void _showError() {
    final message = _currentInputType == 'height' ? 'Enter valid height (1-300 cm)'
                 : _currentInputType == 'weight' ? 'Enter valid weight (1-500 kg)'
                 : 'Enter valid protein (1-500 g)';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showInputDialog(String type) {
    setState(() {
      _currentInputType = type;
      _showInputOverlay = true;
      _inputController.text = type == 'height' ? _height?.toStringAsFixed(1) ?? ''
                          : type == 'weight' ? _weight?.toStringAsFixed(1) ?? ''
                          : '';
    });
  }

  void _cancelInput() {
    setState(() {
      _showInputOverlay = false;
      _selectedLogDate = null;
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
      _selectedLogValue = null;
    });
  }

  void _nextMonth() {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month + 1);
      _icarus = Icarus(date: _currentDate);
      _selectedLogDate = null;
      _selectedLogValue = null;
    });
  }

  void _showActionMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ActionMenu(onSelect: _showInputDialog),
    );
  }

  void _onLogTypeChanged(String? value) {
    if (value != null) {
      setState(() {
        _selectedLogType = value;
        _selectedLogDate = null;
        _selectedLogValue = null;
      });
      _updateLogEntriesMap();
    }
  }

  void _onDayClicked(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    setState(() {
      if (_logEntriesByDate.containsKey(normalizedDay)) {
        _selectedLogDate = normalizedDay;
        _selectedLogValue = _logEntriesByDate[normalizedDay];
      } else {
        _selectedLogDate = null;
        _selectedLogValue = null;
      }
    });
  }

  Color _getDayColor(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final isToday = day.isSameDay(DateTime.now());
    final hasLog = _logEntriesByDate.containsKey(normalizedDay);
    final isSelected = _selectedLogDate == normalizedDay;
    
    if (isToday) return Colors.blue.withOpacity(0.3);
    if (isSelected) return Colors.green.withOpacity(0.5);
    if (hasLog) return Colors.orange.withOpacity(0.4);
    return Colors.transparent;
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
            Expanded(child: _buildCalendarGrid()),
            _buildSelectedDayInfo(),
          ]),
          if (_showInputOverlay) _buildInputOverlay(),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 30.0),
            child: FloatingActionButton(
              onPressed: _createTestData,
              backgroundColor: Colors.orange,
              mini: true,
              child: const Icon(Icons.bug_report),
            ),
          ),
          FloatingActionButton(
            onPressed: _showActionMenu,
            child: const Icon(Icons.menu),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard() => Card(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        _buildBMI(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStat('Weight', _weight, 'kg', _lastWeightUpdate),
            _buildStat('Height', _height, 'cm', null),
          ],
        ),
      ]),
    ),
  );

  Widget _buildBMI() => _bmi != null ? Column(children: [
    Text(_bmi!.toStringAsFixed(1), style: TextStyle(
      fontSize: 24, fontWeight: FontWeight.bold, color: _bmiColor,
    )),
    const SizedBox(height: 4),
    Text(_bmiCategory!, style: TextStyle(fontSize: 14, color: _bmiColor)),
  ]) : const Column(children: [
    Text('--', style: TextStyle(fontSize: 24, color: Colors.grey)),
    const SizedBox(height: 4),
    Text('Enter height & weight', style: TextStyle(fontSize: 14, color: Colors.grey)),
  ]);

  Widget _buildStat(String label, double? value, String unit, DateTime? date) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    Text(value != null ? '${value.toStringAsFixed(1)} $unit' : '-- $unit', 
      style: const TextStyle(fontSize: 14)),
    if (date != null) Text(
      DateFormat('MMM d').format(date),
      style: const TextStyle(fontSize: 10, color: Colors.grey),
    ),
  ]);

  Widget _buildLogSelector() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [
      const Text('Show: ', style: TextStyle(fontSize: 14)),
      const SizedBox(width: 10),
      Expanded(child: DropdownButtonFormField<String>(
        value: _selectedLogType,
        onChanged: _onLogTypeChanged,
        items: const [
          DropdownMenuItem(value: 'weight', child: Text('Weight Logs')),
          DropdownMenuItem(value: 'protein', child: Text('Protein Logs')),
        ],
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      )),
    ]),
  );

  Widget _buildMonthNavigation() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _previousMonth),
        Text(_icarus.monthName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
      ],
    ),
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
        child: Text(_icarus.weekdays[index],
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
    ),
  );

  Widget _buildCalendarGrid() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: _icarus.calendarDays.length,
      itemBuilder: (context, index) => _buildCalendarCell(_icarus.calendarDays[index]),
    ),
  );

  Widget _buildCalendarCell(DateTime day) => GestureDetector(
    onTap: () => _onDayClicked(day),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getDayColor(day),
          border: _getDayColor(day) == Colors.transparent ? null 
            : Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Center(child: Text(
          day.day.toString(),
          style: TextStyle(
            fontSize: 16,
            color: day.month == _icarus.currentMonth ? Colors.white : Colors.grey,
            fontWeight: FontWeight.normal,
          ),
        )),
      ),
    ),
  );

  Widget _buildSelectedDayInfo() {
    if (_selectedLogDate == null || _selectedLogValue == null) {
      return const SizedBox(height: 20);
    }
    
    final unit = _selectedLogType == 'weight' ? 'kg' : 'g';
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        '${_selectedLogValue!.toStringAsFixed(1)} $unit',
        style: const TextStyle(fontSize: 28, color: Colors.white),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentInputType == 'height' ? 'Enter Height' 
                  : _currentInputType == 'weight' ? 'Enter Weight' 
                  : 'Enter Protein',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _inputController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _currentInputType == 'height' ? 'Height' 
                    : _currentInputType == 'weight' ? 'Weight' 
                    : 'Protein',
                  border: const OutlineInputBorder(),
                  suffixText: _currentInputType == 'height' ? 'cm' 
                    : _currentInputType == 'weight' ? 'kg' 
                    : 'g',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: _cancelInput, child: const Text('Cancel')),
                  ElevatedButton(onPressed: _handleSave, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      )),
    ),
  );
}

class ActionMenu extends StatelessWidget {
  final Function(String) onSelect;
  const ActionMenu({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(Icons.height, 'Set Height', 'height', context),
        const SizedBox(height: 10),
        _buildButton(Icons.monitor_weight, 'Log Weight', 'weight', context),
        const SizedBox(height: 10),
        _buildButton(Icons.fitness_center, 'Log Protein', 'protein', context),
      ],
    ),
  );

  Widget _buildButton(IconData icon, String label, String type, BuildContext context) =>
    ElevatedButton.icon(
      onPressed: () { Navigator.pop(context); onSelect(type); },
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
    );
}

class Storage {
  static const String _logFile = 'icarus_log.csv';
  static const String _jsonFile = 'icarus.json';

  static Future<File> _getFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$filename');
  }

  static Future<void> saveHeight(double height) async {
    final file = await _getFile(_jsonFile);
    await file.writeAsString(jsonEncode({'height': height}));
  }

  static Future<double?> loadHeight() async {
    try {
      final file = await _getFile(_jsonFile);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return (json['height'] as num).toDouble();
    } catch (e) {
      print('Error loading height: $e');
      return null;
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
    } catch (e) {
      print('Error loading logs: $e');
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
