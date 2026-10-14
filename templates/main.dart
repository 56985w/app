import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记帐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
  static const String _keyTx = 'transactions_v1';
  static const String _keyBudget = 'monthly_budget';

  static Future<List<Tx>> loadTx() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTx);
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((e) => Tx.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveTx(List<Tx> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyTx,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future<double> loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyBudget) ?? 0.0;
  }

  static Future<void> saveBudget(double budget) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBudget, budget);
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
  double _budget = 0.0;
  String _timeFilter = '全部'; // '全部', '一年', '一月'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Store.loadTx();
    final b = await Store.loadBudget();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _txs = list;
      _budget = b;
      _loading = false;
    });
  }

  // 获取当前过滤时间段内的数据
  List<Tx> get _filteredTxs {
    if (_timeFilter == '全部') return _txs;
    final now = DateTime.now();
    if (_timeFilter == '一年') {
      final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
      return _txs.where((t) => t.date.isAfter(oneYearAgo)).toList();
    } else if (_timeFilter == '一月') {
      final oneMonthAgo = DateTime(now.year, now.month - 1, now.day);
      return _txs.where((t) => t.date.isAfter(oneMonthAgo)).toList();
    }
    return _txs;
  }

  // 计算总收支
  double get _income =>
      _filteredTxs.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double get _expense =>
      _filteredTxs.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double get _balance => _income - _expense;

  // 计算本月支出（用于预算判断）
  double get _currentMonthExpense {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    return _txs
        .where((t) => !t.isIncome && t.date.isAfter(startOfMonth))
        .fold(0.0, (s, t) => s + t.amount);
  }

  // 分类统计（用于图表）
  Map<String, double> get _categoryStats {
    final Map<String, double> stats = {};
    for (var t in _filteredTxs.where((t) => !t.isIncome)) {
      stats[t.category] = (stats[t.category] ?? 0) + t.amount;
    }
    return stats;
  }

  Future<void> _openAdd() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPage()),
    );
    if (changed == true) _load();
  }

  Future<void> _setBudget() async {
    final controller = TextEditingController(text: _budget.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置每月预算'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '¥ ', labelText: '预算金额'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) Navigator.pop(ctx, val);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await Store.saveBudget(result);
      _load();
    }
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定删除这条记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      final list = [..._txs];
      list.removeAt(index);
      await Store.saveTx(list);
      _load();
    }
  }

  String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // 判断预算是否超支
    final bool isOverBudget = _budget > 0 && _currentMonthExpense > _budget;
    final double budgetProgress = _budget > 0 ? (_currentMonthExpense / _budget).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记帐'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: _setBudget,
            tooltip: '设置预算',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 1. 余额与总收支卡片
                _buildBalanceCard(),
                const SizedBox(height: 12),
                
                // 2. 预算与提醒卡片
                _buildBudgetCard(isOverBudget, budgetProgress),
                const SizedBox(height: 12),

                // 3. 图表统计卡片
                _buildChartCard(),
                const SizedBox(height: 12),

                // 4. 账单列表
                const Text('交易明细', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                _txs.isEmpty
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('暂无记录，点右下角 + 开始记账'),
                      ))
                    : Column(
                        children: _filteredTxs.asMap().entries.map((entry) {
                          final index = entry.key;
                          final t = entry.value;
                          final color = t.isIncome ? Colors.green : Colors.red;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withOpacity(0.1),
                                child: Icon(
                                  t.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
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
                              onLongPress: () => _delete(_txs.indexOf(t)),
                            ),
                          );
                        }).toList(),
                      ),
              ],
            ),
    );
  }

  // 余额卡片 UI
  Widget _buildBalanceCard() {
    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('当前结余', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              '¥${_balance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  const Text('总收入', style: TextStyle(color: Colors.green)),
                  const SizedBox(height: 4),
                  Text('¥${_income.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ]),
                Column(children: [
                  const Text('总支出', style: TextStyle(color: Colors.red)),
                  const SizedBox(height: 4),
                  Text('¥${_expense.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 预算卡片 UI
  Widget _buildBudgetCard(bool isOver, double progress) {
    if (_budget <= 0) {
      return Card(
        child: ListTile(
          title: const Text('未设置月度预算'),
          subtitle: const Text('点击设置，控制每月开销'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _setBudget,
        ),
      );
    }

    return Card(
      color: isOver ? Colors.red.withOpacity(0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('本月预算: ¥${_budget.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('已用: ¥${_currentMonthExpense.toStringAsFixed(2)}', 
                  style: TextStyle(color: isOver ? Colors.red : Colors.grey[700], fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              color: isOver ? Colors.red : Colors.teal,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            if (isOver)
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                  SizedBox(width: 4),
                  Text('警告：本月支出已超过预算！', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              )
            else
              Text('剩余: ¥${(_budget - _currentMonthExpense).toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal)),
          ],
        ),
      ),
    );
  }

  // 图表统计卡片 UI
  Widget _buildChartCard() {
    final stats = _categoryStats;
    if (stats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('暂无支出数据，无法生成图表')),
        ),
      );
    }

    // 准备饼图数据
    final List<Color> colors = [
      Colors.teal, Colors.blue, Colors.orange, Colors.purple, Colors.pink,
      Colors.red, Colors.green, Colors.amber, Colors.indigo, Colors.cyan
    ];
    int colorIndex = 0;
    final List<PieChartSectionData> sections = [];
    stats.forEach((category, amount) {
      sections.add(PieChartSectionData(
        color: colors[colorIndex % colors.length],
        value: amount,
        title: '${(amount / _expense * 100).toStringAsFixed(1)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
      colorIndex++;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('支出统计', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                // 时间切换
                ToggleButtons(
                  isSelected: [_timeFilter == '全部', _timeFilter == '一年', _timeFilter == '一月'],
                  onPressed: (index) {
                    setState(() {
                      _timeFilter = ['全部', '一年', '一月'][index];
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 28, minWidth: 45),
                  children: const [
                    Text('全部', style: TextStyle(fontSize: 12)),
                    Text('一年', style: TextStyle(fontSize: 12)),
                    Text('一月', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 图例
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: stats.keys.toList().asMap().entries.map((entry) {
                final color = colors[entry.key % colors.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, color: color),
                    const SizedBox(width: 4),
                    Text(entry.value, style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
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

    final list = await Store.loadTx();
    list.add(tx);
    await Store.saveTx(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

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
            subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
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
