import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'expense_controller.dart';
import 'models.dart';
import 'widgets.dart';

final _digits = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

double? _parse(String s) => double.tryParse(s.replaceAll(',', '').trim());

Widget _amountField(TextEditingController c, {String label = 'Amount (MMK)'}) =>
    TextFormField(
      controller: c,
      autofocus: c.text.isEmpty,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_digits],
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      validator: (v) {
        final n = _parse(v ?? '');
        if (n == null || n <= 0) return 'Enter an amount';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: 14, right: 8),
          child: Text(
            'Ks',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );

Widget _label(String t) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 8),
  child: Text(
    t,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
  ),
);

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) onChanged(DateTime(d.year, d.month, d.day, 12));
      },
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: AppColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dayLabel(date),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Icon(Icons.edit_calendar_rounded, color: AppColors.muted, size: 20),
        ],
      ),
    );
  }
}

class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in PaymentMethod.all)
          ChoiceChip(
            selected: m.id == value,
            onSelected: (_) => onChanged(m.id),
            showCheckmark: false,
            avatar: PaymentDot(method: m, size: 10),
            label: Text(m.label),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: m.id == value ? FontWeight.w600 : FontWeight.w400,
              color: m.id == value ? m.color : AppColors.text,
            ),
            selectedColor: m.color.withValues(alpha: 0.12),
            backgroundColor: AppColors.card,
            side: BorderSide(color: m.id == value ? m.color : AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Expense sheet
// ===========================================================================

Future<void> showExpenseSheet(
  BuildContext context,
  ExpenseController ctrl, {
  Expense? existing,
  DateTime? date,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExpenseSheet(ctrl: ctrl, existing: existing, date: date),
  ).then((status) async {
    if (status == BudgetStatus.danger && context.mounted) {
      // Wait for the controller to receive the new data, then alert.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (context.mounted) {
        await showEmergencyDialog(
          context,
          ctrl.summary,
          ownerName: ctrl.partnerView
              ? (ctrl.ownerName ?? 'Your partner')
              : null,
        );
      }
    } else if (status == BudgetStatus.warning && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFB7791F),
          content: Text(
            'Careful: you have used 80% of this month\'s spending budget.',
          ),
        ),
      );
    }
  });
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.ctrl, this.existing, this.date});
  final ExpenseController ctrl;
  final Expense? existing;
  final DateTime? date;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _category;
  late String _payment;
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
      text: e == null ? '' : money(e.amount).replaceAll(',', ''),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.categoryId ?? 'food';
    _payment = e?.paymentId ?? 'cash';
    final now = DateTime.now();
    _date =
        e?.date ??
        widget.date ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final status = await widget.ctrl.saveExpense(
        Expense(
          id: widget.existing?.id ?? '',
          amount: _parse(_amount.text)!,
          categoryId: _category,
          paymentId: _payment,
          date: _date,
          note: _note.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, status);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, 'this expense');
    if (!ok) return;
    await widget.ctrl.deleteExpense(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Add expense' : 'Edit expense',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _amountField(_amount),
              _label('Date'),
              _DateField(
                date: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
              _label('Category'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
                children: [
                  for (final c in ExpenseCategory.all)
                    _CategoryTile(
                      c: c,
                      selected: c.id == _category,
                      onTap: () => setState(() => _category = c.id),
                    ),
                ],
              ),
              _label('Paid with'),
              _PaymentPicker(
                value: _payment,
                onChanged: (v) => setState(() => _payment = v),
              ),
              _label('Note (optional)'),
              TextFormField(
                controller: _note,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Lunch at Shwe Ba, Grab to office',
                  prefixIcon: Icon(Icons.notes_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                ),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.existing == null
                            ? 'Save expense'
                            : 'Update expense',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.c,
    required this.selected,
    required this.onTap,
  });
  final ExpenseCategory c;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? c.color.withValues(alpha: 0.12) : AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? c.color : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(c.icon, color: c.color, size: 24),
            const SizedBox(height: 4),
            Text(
              c.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Salary sheet
// ===========================================================================

Future<void> showSalarySheet(
  BuildContext context,
  ExpenseController ctrl, {
  Salary? existing,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SalarySheet(ctrl: ctrl, existing: existing),
  );
}

class _SalarySheet extends StatefulWidget {
  const _SalarySheet({required this.ctrl, this.existing});
  final ExpenseController ctrl;
  final Salary? existing;

  @override
  State<_SalarySheet> createState() => _SalarySheetState();
}

class _SalarySheetState extends State<_SalarySheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _source;
  late String _payment;
  late DateTime _date;
  bool _busy = false;

  static const _sources = [
    'Salary',
    'Bonus',
    'Overtime',
    'Freelance',
    'Business',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _amount = TextEditingController(
      text: s == null ? '' : s.amount.round().toString(),
    );
    final n = widget.ctrl.summary.salaries.length + 1;
    _source = TextEditingController(
      text: s?.source ?? (n == 1 ? 'Salary' : 'Salary $n'),
    );
    _payment = s?.paymentId ?? 'bank';
    final now = DateTime.now();
    final m = widget.ctrl.month;
    // Default date: today if viewing the current month, else the 1st of that month.
    _date =
        s?.date ??
        (m.year == now.year && m.month == now.month
            ? DateTime(now.year, now.month, now.day, 12)
            : DateTime(m.year, m.month, 1, 12));
  }

  @override
  void dispose() {
    _amount.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.ctrl.saveSalary(
        Salary(
          id: widget.existing?.id ?? '',
          amount: _parse(_amount.text)!,
          source: _source.text.trim().isEmpty ? 'Salary' : _source.text.trim(),
          date: _date,
          paymentId: _payment,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, 'this salary');
    if (!ok) return;
    await widget.ctrl.deleteSalary(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add salary / income'
                          : 'Edit salary',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Got paid more than once this month? Add each payment separately – '
                'they are combined into your total salary.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              _amountField(_amount),
              _label('Source'),
              TextFormField(
                controller: _source,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in _sources)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _source.text = s),
                      backgroundColor: AppColors.card,
                      side: BorderSide(color: AppColors.border),
                    ),
                ],
              ),
              _label('Received on'),
              _DateField(
                date: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
              _label('Received to'),
              _PaymentPicker(
                value: _payment,
                onChanged: (v) => setState(() => _payment = v),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.existing == null
                            ? 'Save salary'
                            : 'Update salary',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Keep amount sheet
// ===========================================================================

Future<void> showKeepSheet(BuildContext context, ExpenseController ctrl) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _KeepSheet(ctrl: ctrl),
  );
}

class _KeepSheet extends StatefulWidget {
  const _KeepSheet({required this.ctrl});
  final ExpenseController ctrl;
  @override
  State<_KeepSheet> createState() => _KeepSheetState();
}

class _KeepSheetState extends State<_KeepSheet> {
  late bool _custom;
  late double _percent;
  late final TextEditingController _amount;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final s = widget.ctrl.summary;
    _custom = s.isCustomKeep;
    _percent = s.settings.keepPercent;
    _amount = TextEditingController(
      text: s.isCustomKeep ? s.settings.customKeep!.round().toString() : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_custom) {
      if (!_form.currentState!.validate()) return;
      await widget.ctrl.setCustomKeep(_parse(_amount.text));
    } else {
      await widget.ctrl.setKeepPercent(_percent);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.ctrl.summary;
    final auto = s.totalSalary * _percent / 100;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Keep amount for ${monthLabel(s.month)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This is the money you want to have left at the end of the month. '
                'You will get an emergency alert if your balance drops below it.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Auto'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('My amount'),
                    icon: Icon(Icons.edit),
                  ),
                ],
                selected: {_custom},
                onSelectionChanged: (v) => setState(() => _custom = v.first),
              ),
              const SizedBox(height: 18),
              if (!_custom) ...[
                AppCard(
                  color: AppColors.purpleLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keep ${_percent.round()}% of salary',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        mmk(auto),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Based on total salary ${mmk(s.totalSalary)}. '
                        '20% follows the popular 50/30/20 budgeting rule.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: _percent,
                  min: 5,
                  max: 70,
                  divisions: 13,
                  label: '${_percent.round()}%',
                  onChanged: (v) => setState(() => _percent = v),
                ),
              ] else
                _amountField(_amount, label: 'Amount to keep (MMK)'),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _save,
                child: const Text('Save keep amount'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('Delete', style: TextStyle(color: AppColors.red)),
        ),
      ],
    ),
  );
  return ok == true;
}
