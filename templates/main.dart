import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记账本',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class Tx {
  final String id;
  final double amount;
  final bool isIncome;
  final String category;
  final String note;
  final DateTime date;

  Tx({
    required this.id,
    required this.amount,
    required this.isIncome,
    required this.category,
    required this.note,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'isIncome': isIncome,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
      };

  factory Tx.fromJson(Map<String, dynamic> json) => Tx(
        id: json['id'] as String? ?? '',
        amount: (json['amount'] as num).toDouble(),
        isIncome: json['isIncome'] as bool? ?? false,
        category: json['category'] as String? ?? '其他',
        note: json['note'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      );
}

class Store {
  static const String _key = 'transactions_v1';

  static Future<List<Tx>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => Tx.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<Tx> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Tx> _txs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Store.load();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _txs = list;
      _loading = false;
    });
  }

  double get _income =>
      _txs.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double get _expense =>
      _txs.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double get _balance => _income - _expense;

  Future<void> _openAdd() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPage()),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final list = [..._txs];
      list.removeAt(index);
      await Store.save(list);
      _load();
    }
  }

  String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _sumItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color)),
        const SizedBox(height: 4),
        Text(
          '¥${value.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账本'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      const Text('当前余额'),
                      const SizedBox(height: 6),
                      Text(
                        '¥${_balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _sumItem('收入', _income, Colors.green),
                          _sumItem('支出', _expense, Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _txs.isEmpty
                      ? const Center(child: Text('还没有记录，点右下角 + 添加'))
                      : ListView.separated(
                          itemCount: _txs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = _txs[index];
                            final color =
                                t.isIncome ? Colors.green : Colors.red;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withAlpha(30),
                                child: Icon(
                                  t.isIncome
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                                  color: color,
                                ),
                              ),
                              title: Text(t.category),
                              subtitle: Text(
                                '${_dateText(t.date)}${t.note.isEmpty ? '' : ' · ${t.note}'}',
                              ),
                              trailing: Text(
                                '${t.isIncome ? '+' : '-'}¥${t.amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              onLongPress: () => _delete(index),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  bool _isIncome = false;
  String _category = '餐饮';
  DateTime _date = DateTime.now();

  List<String> get _categories => _isIncome
      ? ['工资', '奖金', '理财', '红包', '其他']
      : ['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '其他'];

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确金额')),
      );
      return;
    }

    final tx = Tx(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: value,
      isIncome: _isIncome,
      category: _category,
      note: _note.text.trim(),
      date: _date,
    );

    final list = await Store.load();
    list.add(tx);
    await Store.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final categories = _categories;

    return Scaffold(
      appBar: AppBar(title: const Text('添加记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('支出'),
                selected: !_isIncome,
                onSelected: (_) {
                  setState(() {
                    _isIncome = false;
                    _category = '餐饮';
                  });
                },
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('收入'),
                selected: _isIncome,
                onSelected: (_) {
                  setState(() {
                    _isIncome = true;
                    _category = '工资';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: '分类',
              border: OutlineInputBorder(),
            ),
            items: categories
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) {
              setState(() => _category = v ?? categories.first);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('日期'),
            subtitle: Text(_dateText(_date)),
            trailing: const Icon(Icons.calendar_month),
            onTap: _pickDate,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
