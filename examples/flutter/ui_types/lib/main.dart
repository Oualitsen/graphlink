import 'package:flutter/material.dart';
import 'package:flutter_ui_example/generated/enums/fuel_type.dart';
import 'package:flutter_ui_example/generated/inputs/add_vehicle_input.dart';
import 'package:flutter_ui_example/generated/inputs/event_input.dart';
import 'package:flutter_ui_example/generated/inputs/register_input.dart';
import 'package:flutter_ui_example/generated/types/fleet.dart';
import 'package:flutter_ui_example/generated/types/owner.dart';
import 'package:flutter_ui_example/generated/types/vehicle.dart';
import 'package:flutter_ui_example/generated/widgets/types/fleet_widget.dart';
import 'package:flutter_ui_example/generated/widgets/types/owner_widget.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/add_vehicle_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/boolean_labels.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/date_input_config.dart';
import 'package:flutter_ui_example/generated/inputs/person_input.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/event_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/form_strings.dart';
import 'package:flutter_ui_example/generated/inputs/address_input.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/input_step_options.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/address_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/person_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/simple_field_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/field_widgets.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/field_visibility.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/input_read_exception.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/required_indicator.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/register_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/text_field_options.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/update_vehicle_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/inputs/vehicle_search_input_form.dart';
import 'package:flutter_ui_example/generated/widgets/types/vehicle_widget.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GraphLink Flutter UI Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: DefaultTabController(
        length: 15,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('GraphLink Flutter UI'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Display'),
                Tab(text: 'Add Vehicle'),
                Tab(text: 'Hidden Fields'),
                Tab(text: 'Update'),
                Tab(text: 'Search'),
                Tab(text: 'Field Widgets'),
                Tab(text: 'Text Options'),
                Tab(text: 'Chip Validation'),
                Tab(text: 'Date Inputs'),
                Tab(text: 'Composition'),
                Tab(text: 'Type Widgets'),
                Tab(text: 'Dynamic Forms'),
                Tab(text: 'onChange'),
                Tab(text: 'Stepper'),
                Tab(text: 'Expandable'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _DisplayTab(),
              _AddVehicleTab(),
              _HiddenFieldsTab(),
              _UpdateVehicleTab(),
              _SearchTab(),
              _FieldWidgetsTab(),
              _TextOptionsTab(),
              _ChipValidationTab(),
              _DateInputsTab(),
              _CompositionTab(),
              _TypeWidgetsTab(),
              _DynamicFormsTab(),
              _OnChangeTab(),
              _StepperTab(),
              _ExpandableTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab 1: Display widgets ─────────────────────────────────────────────────────

class _DisplayTab extends StatefulWidget {
  const _DisplayTab();

  @override
  State<_DisplayTab> createState() => _DisplayTabState();
}

class _DisplayTabState extends State<_DisplayTab> {
  VehicleLayout _layout = VehicleLayout.labeledRow;
  double _gap = 16;
  bool _hideNotes = false;
  bool _customLabel = false;
  bool _fuelChip = false;
  bool _notesFirst = false;

  static Vehicle _sampleVehicle() => Vehicle(
        id: '1',
        brand: 'Toyota',
        model: 'Camry',
        year: 2023,
        fuelType: FuelType.HYBRID,
        available: true,
        mileage: 12500.5,
        notes: 'Great condition',
      );

  @override
  Widget build(BuildContext context) {
    final v = _sampleVehicle();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Layout selector ─────────────────────────────────────────────────
          Text('Layout', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownMenu<VehicleLayout>(
            initialSelection: _layout,
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _layout = v ?? _layout),
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: VehicleLayout.labeledRow, label: 'Aligned row'),
              DropdownMenuEntry(value: VehicleLayout.listTile, label: 'List tile'),
              DropdownMenuEntry(value: VehicleLayout.listTileReversed, label: 'List tile (reversed)'),
            ],
          ),

          // ── Gap slider ──────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Gap', style: theme.textTheme.bodySmall),
              Expanded(
                child: Slider(
                  value: _gap,
                  min: 4,
                  max: 32,
                  divisions: 7,
                  label: '${_gap.toInt()} px',
                  onChanged: (v) => setState(() => _gap = v),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text('${_gap.toInt()} px', style: theme.textTheme.bodySmall),
              ),
            ],
          ),

          // ── Options ─────────────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Hide notes'),
                selected: _hideNotes,
                onSelected: (on) => setState(() => _hideNotes = on),
              ),
              FilterChip(
                label: const Text('"Make" label'),
                selected: _customLabel,
                onSelected: (on) => setState(() => _customLabel = on),
              ),
              FilterChip(
                label: const Text('Fuel chip'),
                selected: _fuelChip,
                onSelected: (on) => setState(() => _fuelChip = on),
              ),
              FilterChip(
                label: const Text('Notes first'),
                selected: _notesFirst,
                onSelected: (on) => setState(() => _notesFirst = on),
              ),
            ],
          ),

          const Divider(height: 32),

          // ── VehicleWidget ────────────────────────────────────────────────────
          VehicleWidget(
            v,
            layout: _layout,
            gap: _gap,
            labels: _customLabel ? const VehicleLabels(brand: Text('Make')) : null,
            values: _fuelChip ? VehicleValues(fuelType: Chip(label: Text(v.fuelType.name))) : null,
            visibility: _hideNotes ? const VehicleVisibility(notes: false) : null,
            order: _notesFirst ? const VehicleOrder(notes: 0) : null,
          ),

          // ── Table row (always shown) ─────────────────────────────────────────
          const SizedBox(height: 32),
          Text('Table row', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(),
            children: [
              VehicleWidget(v).toTableHeaderRow(),
              VehicleWidget(v).toTableRow(),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Form options playground ───────────────────────────────────────────

class _AddVehicleTab extends StatefulWidget {
  const _AddVehicleTab();

  @override
  State<_AddVehicleTab> createState() => _AddVehicleTabState();
}

class _AddVehicleTabState extends State<_AddVehicleTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();
  AddVehicleInput? _result;

  AddVehicleInputLabelPosition _labelPosition = AddVehicleInputLabelPosition.floatingLabel;
  AddVehicleInputLayout _layout = AddVehicleInputLayout.column;
  double _labelWidth = 120;
  bool _customOrder = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Label position ──────────────────────────────────────────────────
          Text('Label position', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AddVehicleInputLabelPosition>(
            segments: const [
              ButtonSegment(
                value: AddVehicleInputLabelPosition.beside,
                label: Text('Beside'),
                icon: Icon(Icons.view_week_outlined),
              ),
              ButtonSegment(
                value: AddVehicleInputLabelPosition.above,
                label: Text('Above'),
                icon: Icon(Icons.view_agenda_outlined),
              ),
              ButtonSegment(
                value: AddVehicleInputLabelPosition.floatingLabel,
                label: Text('Floating'),
                icon: Icon(Icons.text_fields),
              ),
            ],
            selected: {_labelPosition},
            onSelectionChanged: (s) => setState(() => _labelPosition = s.first),
          ),

          // Label width slider — only relevant for beside mode
          if (_labelPosition == AddVehicleInputLabelPosition.beside) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Label width', style: theme.textTheme.bodySmall),
                Expanded(
                  child: Slider(
                    value: _labelWidth,
                    min: 60,
                    max: 220,
                    divisions: 16,
                    label: '${_labelWidth.toInt()} px',
                    onChanged: (v) => setState(() => _labelWidth = v),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text('${_labelWidth.toInt()} px', style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Layout ──────────────────────────────────────────────────────────
          Text('Layout', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AddVehicleInputLayout>(
            segments: const [
              ButtonSegment(
                value: AddVehicleInputLayout.column,
                label: Text('Column'),
                icon: Icon(Icons.view_stream_outlined),
              ),
              ButtonSegment(
                value: AddVehicleInputLayout.twoColumn,
                label: Text('Two-col'),
                icon: Icon(Icons.view_column_outlined),
              ),
            ],
            selected: {_layout},
            onSelectionChanged: (s) => setState(() => _layout = s.first),
          ),

          const SizedBox(height: 16),

          // ── Field order ─────────────────────────────────────────────────────
          Text('Field order', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Schema order'),
                icon: Icon(Icons.sort_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Custom order'),
                icon: Icon(Icons.swap_vert),
              ),
            ],
            selected: {_customOrder},
            onSelectionChanged: (s) => setState(() => _customOrder = s.first),
          ),

          const Divider(height: 32),

          // ── The form ────────────────────────────────────────────────────────
          AddVehicleInputForm(
            key: _key,
            layout: _layout,
            labelPosition: _labelPosition,
            labelWidth: _labelWidth,
            order: _customOrder
                ? const AddVehicleInputOrder(
                    fuelType: 0,
                    available: 1,
                    year: 2,
                    brand: 3,
                    model: 4,
                    mileage: 5,
                    notes: 6,
                  )
                : null,
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result = input);
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 3: Hidden fields + defaults ──────────────────────────────────────────

class _HiddenFieldsTab extends StatefulWidget {
  const _HiddenFieldsTab();

  @override
  State<_HiddenFieldsTab> createState() => _HiddenFieldsTabState();
}

class _HiddenFieldsTabState extends State<_HiddenFieldsTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();
  AddVehicleInput? _result;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Hidden fields with defaults — "available" and "fuelType" are hidden.\n'
            'Their values are supplied via hiddenDefaults at construction time.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          AddVehicleInputForm(
            key: _key,
            layout: AddVehicleInputLayout.column,
            // hide two fields — their values come from hiddenDefaults
            visibility: const AddVehicleInputVisibility(
              available: _hidden,
              fuelType: _hidden,
            ),
            hiddenDefaults: const AddVehicleInputDefaults(
              available: true,
              fuelType: FuelType.ELECTRIC,
            ),
            // custom labels
            labels: const AddVehicleInputLabels(
              brand: Text('Make'),
              year: Text('Year (e.g. 2024)'),
            ),
            // custom validator — receives (value, formContext)
            validations: AddVehicleInputValidations(
              year: (v, ctx) {
                final y = int.tryParse(v ?? '');
                if (y != null && (y < 1990 || y > 2030)) return 'Year must be between 1990 and 2030';
                return null;
              },
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result = input);
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 4: UpdateVehicleInputForm ─────────────────────────────────────────────

class _UpdateVehicleTab extends StatefulWidget {
  const _UpdateVehicleTab();

  @override
  State<_UpdateVehicleTab> createState() => _UpdateVehicleTabState();
}

class _UpdateVehicleTabState extends State<_UpdateVehicleTab> {
  final _key = GlobalKey<UpdateVehicleInputFormState>();
  String? _result;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Update form — most fields are nullable in the schema.\n'
            '"available" is the only required field.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          UpdateVehicleInputForm(
            key: _key,
            layout: UpdateVehicleInputLayout.column,
            // supply a default for the required hidden-if-needed available field
            hiddenDefaults: const UpdateVehicleInputDefaults(available: false),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit Update'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text(_result!, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result =
          'brand: ${input.brand}\n'
          'model: ${input.model}\n'
          'year: ${input.year}\n'
          'fuelType: ${input.fuelType}\n'
          'available: ${input.available}\n'
          'mileage: ${input.mileage}\n'
          'notes: ${input.notes}');
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 5: VehicleSearchInputForm (list field) ────────────────────────────────

class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _key = GlobalKey<VehicleSearchInputFormState>();
  String? _result;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Search/filter form — fuelTypes is a list-of-enum field rendered as chips.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          VehicleSearchInputForm(
            key: _key,
            layout: VehicleSearchInputLayout.column,
            tagsOptions: const ['sedan', 'suv', 'sport', 'family', 'luxury', 'off-road'],
            labels: const VehicleSearchInputLabels(
              availableOnly: Text('Available only'),
              minYear: Text('Min year'),
              maxMileage: Text('Max mileage (km)'),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Search'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text(_result!, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      final filter = _key.currentState!.read();
      setState(() => _result =
          'fuelTypes: ${filter.fuelTypes.map((f) => f.name).join(', ')}\n'
          'tags: ${filter.tags.join(', ')}\n'
          'availableOnly: ${filter.availableOnly}\n'
          'minYear: ${filter.minYear}\n'
          'maxMileage: ${filter.maxMileage}');
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 6: Per-field widget override ─────────────────────────────────────────

class _FieldWidgetsTab extends StatefulWidget {
  const _FieldWidgetsTab();

  @override
  State<_FieldWidgetsTab> createState() => _FieldWidgetsTabState();
}

class _FieldWidgetsTabState extends State<_FieldWidgetsTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();
  AddVehicleInput? _result;

  EnumFieldWidget _fuelTypeWidget = EnumFieldWidget.dropdown;
  BoolFieldWidget _availableWidget = BoolFieldWidget.chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Per-field widget override',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Each enum/bool field can independently use dropdown, chips, or radio '
            'regardless of the global config. Change the selectors below and watch '
            'the form update live.',
          ),
          const Divider(height: 24),

          // ── fuelType override ───────────────────────────────────────────────
          Text('fuelType widget', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<EnumFieldWidget>(
            segments: const [
              ButtonSegment(
                value: EnumFieldWidget.dropdown,
                label: Text('Dropdown'),
                icon: Icon(Icons.arrow_drop_down_circle_outlined),
              ),
              ButtonSegment(
                value: EnumFieldWidget.chips,
                label: Text('Chips'),
                icon: Icon(Icons.label_outline),
              ),
              ButtonSegment(
                value: EnumFieldWidget.radio,
                label: Text('Radio'),
                icon: Icon(Icons.radio_button_checked_outlined),
              ),
            ],
            selected: {_fuelTypeWidget},
            onSelectionChanged: (s) => setState(() => _fuelTypeWidget = s.first),
          ),

          const SizedBox(height: 16),

          // ── available override ──────────────────────────────────────────────
          Text('available widget', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<BoolFieldWidget>(
            segments: const [
              ButtonSegment(
                value: BoolFieldWidget.chips,
                label: Text('Chips'),
                icon: Icon(Icons.label_outline),
              ),
              ButtonSegment(
                value: BoolFieldWidget.radio,
                label: Text('Radio'),
                icon: Icon(Icons.radio_button_checked_outlined),
              ),
            ],
            selected: {_availableWidget},
            onSelectionChanged: (s) => setState(() => _availableWidget = s.first),
          ),

          const Divider(height: 24),

          // ── The form ────────────────────────────────────────────────────────
          AddVehicleInputForm(
            key: _key,
            widgets: AddVehicleInputWidgets(
              fuelType: _fuelTypeWidget,
              available: _availableWidget,
            ),
            dropdownLabels: const AddVehicleInputDropdownLabels(
              available: BooleanLabels(
                trueLabel: Text('In stock'),
                falseLabel: Text('Out of stock'),
              ),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitWidgets,
            child: const Text('Submit'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }

  void _submitWidgets() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result = input);
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 7: TextFieldOptions / password / smart defaults ───────────────────────

class _TextOptionsTab extends StatefulWidget {
  const _TextOptionsTab();

  @override
  State<_TextOptionsTab> createState() => _TextOptionsTabState();
}

class _TextOptionsTabState extends State<_TextOptionsTab> {
  final _key = GlobalKey<RegisterInputFormState>();
  RegisterInput? _result;

  bool _addPrefixIcons = true;
  bool _addBioMaxLines = true;
  bool _addUsernameLimit = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Text Options', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Smart defaults are baked in by field name at generation time. '
            'Toggle the options below to see textConfig overrides applied on top.',
          ),
          const Divider(height: 20),

          // ── Smart defaults summary ──────────────────────────────────────────
          Text('Smart defaults (always active)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: const [
              Chip(
                avatar: Icon(Icons.email_outlined, size: 16),
                label: Text('email → emailAddress keyboard'),
              ),
              Chip(
                avatar: Icon(Icons.lock_outline, size: 16),
                label: Text('password → obscured + toggle'),
              ),
              Chip(
                avatar: Icon(Icons.phone_outlined, size: 16),
                label: Text('phone → phone keyboard'),
              ),
              Chip(
                avatar: Icon(Icons.link_outlined, size: 16),
                label: Text('website → url keyboard'),
              ),
            ],
          ),

          const Divider(height: 20),

          // ── textConfig overrides ────────────────────────────────────────────
          Text('textConfig overrides', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Prefix icons'),
                selected: _addPrefixIcons,
                onSelected: (on) => setState(() => _addPrefixIcons = on),
              ),
              FilterChip(
                label: const Text('bio → maxLines: 3'),
                selected: _addBioMaxLines,
                onSelected: (on) => setState(() => _addBioMaxLines = on),
              ),
              FilterChip(
                label: const Text('username maxLength: 20'),
                selected: _addUsernameLimit,
                onSelected: (on) => setState(() => _addUsernameLimit = on),
              ),
            ],
          ),

          const Divider(height: 20),

          // ── The form ────────────────────────────────────────────────────────
          RegisterInputForm(
            key: _key,
            textConfig: RegisterInputTextConfig(
              username: TextFieldOptions(
                maxLength: _addUsernameLimit ? 20 : null,
                decoration: _addPrefixIcons
                    ? (d) => d.copyWith(prefixIcon: const Icon(Icons.person_outline))
                    : null,
              ),
              email: TextFieldOptions(
                decoration: _addPrefixIcons
                    ? (d) => d.copyWith(prefixIcon: const Icon(Icons.email_outlined))
                    : null,
              ),
              password: TextFieldOptions(
                decoration: _addPrefixIcons
                    ? (d) => d.copyWith(prefixIcon: const Icon(Icons.lock_outline))
                    : null,
              ),
              phone: TextFieldOptions(
                decoration: _addPrefixIcons
                    ? (d) => d.copyWith(prefixIcon: const Icon(Icons.phone_outlined))
                    : null,
              ),
              website: TextFieldOptions(
                decoration: _addPrefixIcons
                    ? (d) => d.copyWith(prefixIcon: const Icon(Icons.link_outlined))
                    : null,
              ),
              bio: TextFieldOptions(
                maxLines: _addBioMaxLines ? 3 : 1,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Register'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _textRow('username', _result!.username),
            _textRow('email', _result!.email),
            _textRow('password', '•' * _result!.password.length),
            _textRow('phone', _result!.phone ?? '—'),
            _textRow('website', _result!.website ?? '—'),
            _textRow('bio', _result!.bio ?? '—'),
          ],
        ],
      ),
    );
  }

  Widget _textRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  void _submit() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result = input);
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 8: Chip validation demo ───────────────────────────────────────────────

class _ChipValidationTab extends StatefulWidget {
  const _ChipValidationTab();

  @override
  State<_ChipValidationTab> createState() => _ChipValidationTabState();
}

class _ChipValidationTabState extends State<_ChipValidationTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();
  AddVehicleInput? _result;
  RequiredIndicator _indicator = RequiredIndicator.none;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Chip Validation + Required Indicator', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Fuel type as chips — submit without selecting to trigger validation. '
            'Toggle the indicator to see all three modes.',
          ),
          const Divider(height: 24),

          Text('Required indicator', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<RequiredIndicator>(
            segments: const [
              ButtonSegment(value: RequiredIndicator.none, label: Text('None')),
              ButtonSegment(value: RequiredIndicator.asterisk, label: Text('*')),
              ButtonSegment(value: RequiredIndicator.requiredText, label: Text('"required"')),
              ButtonSegment(value: RequiredIndicator.optionalText, label: Text('"optional"')),
            ],
            selected: {_indicator},
            onSelectionChanged: (s) => setState(() => _indicator = s.first),
          ),

          const Divider(height: 24),

          AddVehicleInputForm(
            key: _key,
            widgets: const AddVehicleInputWidgets(fuelType: EnumFieldWidget.chips),
            requiredIndicator: _indicator,
            // custom overrides — developer can pass any widget
            requiredLabel: const Text('(mandatory)', style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
            optionalLabel: const Text('(optional)', style: TextStyle(fontSize: 11, color: Colors.grey)),
            visibility: const AddVehicleInputVisibility(
              brand: _hidden,
              model: _hidden,
              year: _hidden,
              available: _hidden,
              mileage: _hidden,
              notes: _hidden,
            ),
            hiddenDefaults: const AddVehicleInputDefaults(
              brand: 'Test',
              model: 'Model',
              year: 2024,
              available: false,
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      final input = _key.currentState!.read();
      setState(() => _result = input);
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 9: Date inputs showcase ───────────────────────────────────────────────

class _DateInputsTab extends StatefulWidget {
  const _DateInputsTab();

  @override
  State<_DateInputsTab> createState() => _DateInputsTabState();
}

class _DateInputsTabState extends State<_DateInputsTab> {
  final _key = GlobalKey<EventInputFormState>();
  EventInput? _result;

  bool _allowKeyboard = true;
  bool _dateTime = false;
  DateInputMode _mode = DateInputMode.dialog;
  bool? _forceCupertino;
  String _intPattern = 'yyyy-MM-dd';
  String _stringPattern = 'dd/MM/yyyy';

  static const _intPatterns = ['yyyy-MM-dd', 'MM/dd/yyyy', 'dd-MM-yyyy'];
  static const _stringPatterns = ['dd/MM/yyyy', 'yyyy-MM-dd', 'MM-dd-yyyy'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateType = _dateTime ? DateType.dateTime : DateType.date;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Date Inputs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'startDate / endDate are Int fields (epoch ms). '
            'eventDate / registrationDeadline are String fields (formatted string). '
            'Toggle the options to see different configurations.',
          ),
          const Divider(height: 24),

          // ── Options ─────────────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.keyboard_outlined, size: 16),
                label: const Text('Keyboard input'),
                selected: _allowKeyboard,
                onSelected: (on) => setState(() => _allowKeyboard = on),
              ),
              FilterChip(
                avatar: const Icon(Icons.access_time_outlined, size: 16),
                label: const Text('Date & time'),
                selected: _dateTime,
                onSelected: (on) => setState(() => _dateTime = on),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Mode ─────────────────────────────────────────────────────────────
          Row(
            children: [
              Text('Mode', style: theme.textTheme.labelSmall),
              const SizedBox(width: 8),
              SegmentedButton<DateInputMode>(
                segments: const [
                  ButtonSegment(value: DateInputMode.dialog, label: Text('Dialog'), icon: Icon(Icons.open_in_new, size: 14)),
                  ButtonSegment(value: DateInputMode.inline, label: Text('Inline'), icon: Icon(Icons.calendar_month_outlined, size: 14)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(width: 16),
              Text('Picker', style: theme.textTheme.labelSmall),
              const SizedBox(width: 8),
              SegmentedButton<bool?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Auto')),
                  ButtonSegment(value: false, label: Text('Material')),
                  ButtonSegment(value: true, label: Text('Cupertino')),
                ],
                selected: {_forceCupertino},
                onSelectionChanged: (s) => setState(() => _forceCupertino = s.first),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Pattern pickers ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Int fields pattern', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    DropdownMenu<String>(
                      initialSelection: _intPattern,
                      expandedInsets: EdgeInsets.zero,
                      onSelected: (v) => setState(() => _intPattern = v ?? _intPattern),
                      dropdownMenuEntries: _intPatterns
                          .map((p) => DropdownMenuEntry(value: p, label: p))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('String fields pattern', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    DropdownMenu<String>(
                      initialSelection: _stringPattern,
                      expandedInsets: EdgeInsets.zero,
                      onSelected: (v) => setState(() => _stringPattern = v ?? _stringPattern),
                      dropdownMenuEntries: _stringPatterns
                          .map((p) => DropdownMenuEntry(value: p, label: p))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Field legend ─────────────────────────────────────────────────────
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(avatar: const Icon(Icons.tag, size: 14), label: Text('startDate → Int! ($_intPattern)')),
              Chip(avatar: const Icon(Icons.tag, size: 14), label: Text('endDate → Int? ($_intPattern)')),
              Chip(avatar: const Icon(Icons.abc, size: 14), label: Text('eventDate → String! ($_stringPattern)')),
              Chip(avatar: const Icon(Icons.abc, size: 14), label: Text('registrationDeadline → String? ($_stringPattern)')),
            ],
          ),

          const Divider(height: 24),

          // ── The form ─────────────────────────────────────────────────────────
          EventInputForm(
            key: _key,
            dateConfig: EventInputDateConfig(
              startDate: DateInputConfig(
                type: dateType,
                mode: _mode,
                pattern: _intPattern,
                allowKeyboardInput: _allowKeyboard,
                useCupertino: _forceCupertino,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              ),
              endDate: DateInputConfig(
                type: dateType,
                mode: _mode,
                pattern: _intPattern,
                allowKeyboardInput: _allowKeyboard,
                useCupertino: _forceCupertino,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              ),
              eventDate: DateInputConfig(
                type: dateType,
                mode: _mode,
                pattern: _stringPattern,
                allowKeyboardInput: _allowKeyboard,
                useCupertino: _forceCupertino,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              ),
              registrationDeadline: DateInputConfig(
                type: dateType,
                mode: _mode,
                pattern: _stringPattern,
                allowKeyboardInput: _allowKeyboard,
                useCupertino: _forceCupertino,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              ),
            ),
            labels: const EventInputLabels(
              startDate: Text('Start date (Int → epoch ms)'),
              endDate: Text('End date (Int → epoch ms, optional)'),
              eventDate: Text('Event date (String)'),
              registrationDeadline: Text('Registration deadline (String, optional)'),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(onPressed: _submit, child: const Text('Submit')),

          // ── Result ───────────────────────────────────────────────────────────
          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text('Result', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _DateResultCard(result: _result!, intPattern: _intPattern, stringPattern: _stringPattern),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      setState(() => _result = _key.currentState!.read());
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

class _DateResultCard extends StatelessWidget {
  final EventInput result;
  final String intPattern;
  final String stringPattern;
  const _DateResultCard({required this.result, required this.intPattern, required this.stringPattern});

  @override
  Widget build(BuildContext context) {
    String fmtEpoch(int? ms) {
      if (ms == null) return '—';
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '$ms ms  (${DateFormat(intPattern).format(dt)})';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('title', result.title),
            _row('startDate', fmtEpoch(result.startDate)),
            _row('endDate', fmtEpoch(result.endDate)),
            _row('eventDate', result.eventDate),
            _row('registrationDeadline', result.registrationDeadline ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          ],
        ),
      );
}

// ── Tab 11: Type widget showcase ─────────────────────────────────────────────

class _TypeWidgetsTab extends StatefulWidget {
  const _TypeWidgetsTab();
  @override
  State<_TypeWidgetsTab> createState() => _TypeWidgetsTabState();
}

class _TypeWidgetsTabState extends State<_TypeWidgetsTab> {
  OwnerLayout _layout = OwnerLayout.labeledRow;
  bool _hideSecondary = false;
  bool _customStrings = false;

  static Owner _sampleOwner() => Owner(
        name: 'Alice Martin',
        email: 'alice@example.com',
        primaryVehicle: Vehicle(
          id: '1',
          brand: 'Toyota',
          model: 'Camry',
          year: 2023,
          fuelType: FuelType.HYBRID,
          available: true,
          mileage: 12500.5,
          notes: 'Great condition',
        ),
        secondaryVehicle: Vehicle(
          id: '2',
          brand: 'Tesla',
          model: 'Model 3',
          year: 2024,
          fuelType: FuelType.ELECTRIC,
          available: false,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = _sampleOwner();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type Widget Composition', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'OwnerWidget auto-embeds VehicleWidget for the primaryVehicle and secondaryVehicle '
            'fields — nested type composition with no extra config. '
            'listTileReversed now uses OrdinalSortKey so screen readers announce label first '
            'even though the value appears visually on top.',
          ),
          const Divider(height: 24),

          // ── Layout picker ────────────────────────────────────────────────────
          Text('Layout', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          SegmentedButton<OwnerLayout>(
            segments: const [
              ButtonSegment(value: OwnerLayout.labeledRow, label: Text('Labeled row')),
              ButtonSegment(value: OwnerLayout.listTile, label: Text('List tile')),
              ButtonSegment(value: OwnerLayout.listTileReversed, label: Text('Reversed')),
            ],
            selected: {_layout},
            onSelectionChanged: (s) => setState(() => _layout = s.first),
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Hide secondary vehicle'),
                selected: _hideSecondary,
                onSelected: (on) => setState(() => _hideSecondary = on),
              ),
              FilterChip(
                label: const Text('French strings'),
                selected: _customStrings,
                onSelected: (on) => setState(() => _customStrings = on),
              ),
            ],
          ),

          const Divider(height: 24),

          OwnerWidget(
            owner,
            layout: _layout,
            visibility: _hideSecondary
                ? const OwnerVisibility(secondaryVehicle: false)
                : null,
            strings: _customStrings
                ? const FormStrings(yes: 'Oui', no: 'Non')
                : const FormStrings(),
            labels: const OwnerLabels(
              primaryVehicle: Text('Primary vehicle', style: TextStyle(fontWeight: FontWeight.w600)),
              secondaryVehicle: Text('Secondary vehicle', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),

          const Divider(height: 24),
          Text('Table view', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(color: Colors.grey.shade300),
            children: [
              OwnerWidget(owner).toTableHeaderRow(),
              OwnerWidget(owner).toTableRow(),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab 10: Nested input composition ─────────────────────────────────────────

class _CompositionTab extends StatefulWidget {
  const _CompositionTab();
  @override
  State<_CompositionTab> createState() => _CompositionTabState();
}

class _CompositionTabState extends State<_CompositionTab> {
  final _key = GlobalKey<PersonInputFormState>();
  PersonInput? _result;
  String _locale = 'en';
  String? _country;

  static const _countries = [
    'Algeria',
    'Canada',
    'France',
    'Germany',
    'Italy',
    'Morocco',
    'Spain',
    'Tunisia',
    'United Kingdom',
    'United States',
  ];

  FormStrings _stringsFor(String locale) => switch (locale) {
        'fr' => const FormStrings(
            required: 'Obligatoire',
            mustBeWholeNumber: 'Doit être un entier',
            mustBeNumber: 'Doit être un nombre',
            invalidDate: 'Date invalide',
            chooseAnOption: 'Choisir une option',
            yes: 'Oui',
            no: 'Non',
            showPassword: 'Afficher le mot de passe',
            hidePassword: 'Masquer le mot de passe',
            requiredText: 'obligatoire',
            optionalText: 'optionnel',
            pickDate: 'Choisir une date',
            pickDateAndTime: 'Choisir date et heure',
            cancel: 'Annuler',
            done: 'Terminé',
          ),
        'ar' => const FormStrings(
            required: 'مطلوب',
            mustBeWholeNumber: 'يجب أن يكون عدداً صحيحاً',
            mustBeNumber: 'يجب أن يكون رقماً',
            invalidDate: 'تاريخ غير صالح',
            chooseAnOption: 'اختر خياراً',
            yes: 'نعم',
            no: 'لا',
            showPassword: 'إظهار كلمة المرور',
            hidePassword: 'إخفاء كلمة المرور',
            requiredText: 'مطلوب',
            optionalText: 'اختياري',
            pickDate: 'اختر تاريخاً',
            pickDateAndTime: 'اختر التاريخ والوقت',
            cancel: 'إلغاء',
            done: 'تم',
          ),
        _ => const FormStrings(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nested Input Composition', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'PersonInput embeds AddressInput as a nested field. '
            'The child form validates independently when the parent reads its value. '
            'Also demonstrates FormStrings localization — switch locale to see all error messages change.',
          ),
          const Divider(height: 24),

          // ── Locale picker ────────────────────────────────────────────────────
          Row(
            children: [
              Text('Locale / FormStrings', style: theme.textTheme.labelSmall),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'fr', label: Text('Français')),
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                ],
                selected: {_locale},
                onSelectionChanged: (s) => setState(() => _locale = s.first),
              ),
            ],
          ),

          const Divider(height: 24),

          // ── The form ─────────────────────────────────────────────────────────
          // Sub-input fields are excluded from Values by design — they own their
          // own GlobalKey. To customise AddressInputForm (e.g. restrict country),
          // pass a Values override directly on AddressInputForm and embed
          // PersonInputForm on top for the scalar fields only.
          PersonInputForm(
            key: _key,
            strings: _stringsFor(_locale),
            requiredIndicator: RequiredIndicator.asterisk,
            labels: const PersonInputLabels(
              address: Text('Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),

          const Divider(height: 32),

          // ── AddressInputForm standalone — country restricted to 10 countries ──
          Text('Address (country restricted)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          const Text(
            'Country field replaced via Values override with a SimpleFieldForm<String> '
            'wrapping a dropdown — only 10 countries, Algeria included.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          AddressInputForm(
            strings: _stringsFor(_locale),
            requiredIndicator: RequiredIndicator.asterisk,
            values: AddressInputValues(
              country: (key) => SimpleFieldForm<String>(
                key: key,
                reader: () => _country ??
                    (throw const InputReadException('Country is required')),
                builder: (ctx) => DropdownButtonFormField<String>(
                  value: _country,
                  decoration: const InputDecoration(labelText: 'Country'),
                  hint: const Text('Select a country'),
                  items: _countries
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _country = v),
                  validator: (_) => _country == null ? 'Required' : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(onPressed: _submit, child: const Text('Submit')),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text('Result', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('name', _result!.name),
                    _row('email', _result!.email),
                    _row('street', _result!.address.street),
                    _row('city', _result!.address.city),
                    _row('country', _result!.address.country),
                    _row('zipCode', _result!.address.zipCode ?? '—'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  void _submit() {
    try {
      setState(() => _result = _key.currentState!.read());
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 13: onChange / onContextChange / tryRead ──────────────────────────────

class _OnChangeTab extends StatefulWidget {
  const _OnChangeTab();
  @override
  State<_OnChangeTab> createState() => _OnChangeTabState();
}

class _OnChangeTabState extends State<_OnChangeTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();

  // onContextChange fires synchronously on every keystroke — use for instant UI feedback.
  AddVehicleInputFormContext? _liveContext;

  // onChange fires after the debounce delay and carries a fully parsed AddVehicleInput?.
  // null means the form is currently invalid / not fully filled.
  AddVehicleInput? _debouncedValue;
  DateTime? _lastDebounceAt;

  Duration _debounce = const Duration(milliseconds: 300);
  AddVehicleInput? _submitResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('onChange / onContextChange / tryRead', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '• onContextChange: sync, fires on every field change — drives live UI feedback with zero delay.\n'
            '• onChange: debounced, delivers AddVehicleInput? — null while the form is invalid.\n'
            '• tryRead(): on-demand non-throwing read — useful for save-draft buttons.',
          ),
          const Divider(height: 24),

          // ── Debounce slider ─────────────────────────────────────────────────
          Row(
            children: [
              Text('Debounce', style: theme.textTheme.labelSmall),
              Expanded(
                child: Slider(
                  value: _debounce.inMilliseconds.toDouble(),
                  min: 0,
                  max: 1500,
                  divisions: 15,
                  label: '${_debounce.inMilliseconds} ms',
                  onChanged: (v) => setState(() => _debounce = Duration(milliseconds: v.toInt())),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text('${_debounce.inMilliseconds} ms', style: theme.textTheme.bodySmall),
              ),
            ],
          ),

          const Divider(height: 16),

          // ── Live context panel (onContextChange) ────────────────────────────
          Text('Live context (onContextChange — sync)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_liveContext == null)
            const Text('Start typing to see live context…', style: TextStyle(fontStyle: FontStyle.italic))
          else
            _ContextCard(ctx: _liveContext!),

          const Divider(height: 24),

          // ── Debounced value panel (onChange) ────────────────────────────────
          Row(
            children: [
              Text('Debounced value (onChange)', style: theme.textTheme.labelLarge),
              if (_lastDebounceAt != null) ...[
                const Spacer(),
                Text(
                  'last at ${_lastDebounceAt!.toIso8601String().substring(11, 19)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_debouncedValue == null)
            const Text(
              'null — form is empty or invalid (onChange fires with null until parseable)',
              style: TextStyle(fontStyle: FontStyle.italic),
            )
          else
            _ResultCard(result: _debouncedValue!),

          const Divider(height: 24),

          // ── The form ────────────────────────────────────────────────────────
          AddVehicleInputForm(
            key: _key,
            debounceDuration: _debounce,
            onContextChange: (ctx) {
              // Called synchronously on every field change — no setState needed
              // if you only update derived UI outside the form itself.
              setState(() => _liveContext = ctx);
            },
            onChange: (input) {
              // Called after debounceDuration — input is null if form can't be read.
              setState(() {
                _debouncedValue = input;
                _lastDebounceAt = DateTime.now();
              });
            },
            visibility: AddVehicleInputVisibility(
              notes: (ctx) => ctx.available ? FieldVisibility.enabled : FieldVisibility.hidden,
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Submit (validate + read)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _tryRead,
                  child: const Text('Save draft (tryRead)'),
                ),
              ),
            ],
          ),

          if (_submitResult != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text('Submitted', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _ResultCard(result: _submitResult!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      setState(() => _submitResult = _key.currentState!.read());
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  void _tryRead() {
    final draft = _key.currentState!.tryRead();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          draft == null
              ? 'Draft is incomplete — some required fields missing'
              : 'Draft saved: ${draft.brand} ${draft.model}',
        ),
        backgroundColor: draft == null ? Colors.orange : Colors.green,
      ),
    );
  }
}

// Live context summary card.
class _ContextCard extends StatelessWidget {
  final AddVehicleInputFormContext ctx;
  const _ContextCard({required this.ctx});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _item('brand', ctx.brand.isEmpty ? '—' : ctx.brand),
            _item('model', ctx.model.isEmpty ? '—' : ctx.model),
            _item('year', ctx.year.isEmpty ? '—' : ctx.year),
            _item('fuelType', ctx.fuelType?.name ?? '—'),
            _item('available', ctx.available.toString()),
            _item('mileage', ctx.mileage.isEmpty ? '—' : ctx.mileage),
          ],
        ),
      ),
    );
  }

  Widget _item(String label, String value) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      );
}

// ── Tab 14: Stepper layout ────────────────────────────────────────────────────

class _StepperTab extends StatefulWidget {
  const _StepperTab();
  @override
  State<_StepperTab> createState() => _StepperTabState();
}

class _StepperTabState extends State<_StepperTab> {
  final _key = GlobalKey<PersonInputFormState>();
  PersonInput? _result;

  // Pre-fill to demonstrate edit mode in a stepper.
  bool _prefill = false;

  static PersonInput _sample() => PersonInput(
        name: 'Alice Martin',
        email: 'alice@example.com',
        address: AddressInput(
          street: '12 Rue de la Paix',
          city: 'Paris',
          country: 'France',
          zipCode: '75001',
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Stepper Layout', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'PersonInput has a nested AddressInput, which drives the step structure automatically:\n'
            '  Step 0 — scalar fields: name, email  (validates on Next)\n'
            '  Step 1 — sub-input: address          (calls AddressInputForm.read() on Next)\n\n'
            'Navigation is linear: Next validates + reads the current step before proceeding. '
            'isSkippable bypasses that check for optional review steps. '
            'Tapping a previous step header always works; tapping ahead is blocked.',
          ),
          const Divider(height: 24),

          // ── Options ─────────────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Pre-fill (edit mode)'),
                selected: _prefill,
                onSelected: (on) => setState(() {
                  _prefill = on;
                  _result = null;
                }),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── The stepper form ────────────────────────────────────────────────
          // Key is rebuilt when _prefill changes so initialValues takes effect.
          PersonInputForm(
            key: ValueKey(_prefill),
            layout: PersonInputLayout.stepper,
            initialValues: _prefill ? _sample() : null,
            requiredIndicator: RequiredIndicator.asterisk,

            // Override step titles and add subtitles.
            stepConfig: PersonInputStepConfig(
              scalarFields: const InputStepOptions(
                title: Text('Personal info'),
                subtitle: Text('Your name and contact email'),
              ),
              address: const InputStepOptions(
                title: Text('Address'),
                subtitle: Text('Where should we send your documents?'),
              ),
            ),

            // Cross-field validation across steps:
            // flag suspicious email/name combos at submission time.
            validations: PersonInputValidations(
              email: (v, ctx) {
                if (ctx.name.toLowerCase().contains('test') &&
                    (v?.contains('@example') ?? false)) {
                  return 'Test accounts are not allowed';
                }
                return null;
              },
            ),

            strings: const FormStrings(),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit (final read + validate)'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text('Result (sub-input stepper)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('name', _result!.name),
                    _row('email', _result!.email),
                    const Divider(height: 16),
                    _row('street', _result!.address.street),
                    _row('city', _result!.address.city),
                    _row('country', _result!.address.country),
                    _row('zipCode', _result!.address.zipCode ?? '—'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  void _submit() {
    try {
      setState(() => _result = _key.currentState!.read());
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Tab 15: Expandable layout ─────────────────────────────────────────────────

class _ExpandableTab extends StatefulWidget {
  const _ExpandableTab();
  @override
  State<_ExpandableTab> createState() => _ExpandableTabState();
}

class _ExpandableTabState extends State<_ExpandableTab> {
  bool _customTitle = false;
  bool _hideOwner = false;
  bool _hideVehicles = false;
  FleetLayout _groupLayout = FleetLayout.labeledRow;

  static Fleet _sampleFleet() => Fleet(
        id: 'f1',
        name: 'Sahara Motors',
        city: 'Algiers',
        owner: Owner(
          name: 'Karim Bouzid',
          email: 'karim@saharamotors.dz',
          primaryVehicle: Vehicle(
            id: 'v1',
            brand: 'Toyota',
            model: 'Land Cruiser',
            year: 2022,
            fuelType: FuelType.GASOLINE,
            available: true,
            mileage: 34000,
          ),
        ),
        vehicles: [
          Vehicle(
            id: 'v2',
            brand: 'Renault',
            model: 'Symbol',
            year: 2020,
            fuelType: FuelType.GASOLINE,
            available: true,
            mileage: 78000,
          ),
          Vehicle(
            id: 'v3',
            brand: 'Hyundai',
            model: 'Tucson',
            year: 2023,
            fuelType: FuelType.HYBRID,
            available: false,
            mileage: 12000,
          ),
          Vehicle(
            id: 'v4',
            brand: 'Kia',
            model: 'Sportage',
            year: 2021,
            fuelType: FuelType.DIESEL,
            available: true,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fleet = _sampleFleet();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Expandable Layout', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Fleet has scalar fields (name, city), a nested type (owner: Owner), '
            'and a list of nested types (vehicles: [Vehicle!]). '
            'Each group gets its own accordion. '
            'Scalar fields share one "Details" tile; each complex field has its own.',
          ),
          const Divider(height: 24),

          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Custom "Details" title'),
                selected: _customTitle,
                onSelected: (on) => setState(() => _customTitle = on),
              ),
              FilterChip(
                label: const Text('Hide owner'),
                selected: _hideOwner,
                onSelected: (on) => setState(() => _hideOwner = on),
              ),
              FilterChip(
                label: const Text('Hide vehicles'),
                selected: _hideVehicles,
                onSelected: (on) => setState(() => _hideVehicles = on),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text('Scalar group style', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          SegmentedButton<FleetLayout>(
            segments: const [
              ButtonSegment(value: FleetLayout.labeledRow, label: Text('Labeled row')),
              ButtonSegment(value: FleetLayout.listTile, label: Text('List tile')),
              ButtonSegment(value: FleetLayout.listTileReversed, label: Text('Reversed')),
            ],
            selected: {_groupLayout},
            onSelectionChanged: (s) => setState(() => _groupLayout = s.first),
          ),

          const Divider(height: 24),

          FleetWidget(
            fleet,
            layout: FleetLayout.expandable,
            groupLayout: _groupLayout,
            labels: _customTitle
                ? const FleetLabels($group: Text('Fleet Info', style: TextStyle(fontWeight: FontWeight.w600)))
                : null,
            visibility: FleetVisibility(
              owner: !_hideOwner,
              vehicles: !_hideVehicles,
            ),
          ),
        ],
      ),
    );
  }
}

// Convenience constant — always hides a field regardless of context.
FieldVisibility _hidden(Object? _) => FieldVisibility.hidden;

// ── Tab 12: Dynamic visibility + cross-field validation ───────────────────────

class _DynamicFormsTab extends StatefulWidget {
  const _DynamicFormsTab();
  @override
  State<_DynamicFormsTab> createState() => _DynamicFormsTabState();
}

class _DynamicFormsTabState extends State<_DynamicFormsTab> {
  final _key = GlobalKey<AddVehicleInputFormState>();
  AddVehicleInput? _result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dynamic Forms', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Visibility and validation callbacks receive a live FormContext snapshot '
            'of the current field values, enabling cross-field rules:\n'
            '• notes → hidden when available = false\n'
            '• mileage → disabled when fuelType = ELECTRIC\n'
            '• year validator → rejects < 2010 when fuelType = ELECTRIC',
          ),
          const Divider(height: 24),

          AddVehicleInputForm(
            key: _key,
            visibility: AddVehicleInputVisibility(
              // notes is only relevant when the vehicle is listed as available
              notes: (ctx) => ctx.available
                  ? FieldVisibility.enabled
                  : FieldVisibility.hidden,
              // electric cars don't have a conventional mileage figure — disable, don't hide
              mileage: (ctx) => ctx.fuelType == FuelType.ELECTRIC
                  ? FieldVisibility.disabled
                  : FieldVisibility.enabled,
            ),
            validations: AddVehicleInputValidations(
              // electric vehicles weren't available before 2010
              year: (v, ctx) {
                if (ctx.fuelType == FuelType.ELECTRIC) {
                  final y = int.tryParse(v ?? '');
                  if (y != null && y < 2010) return 'Electric vehicles were not available before 2010';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    try {
      setState(() => _result = _key.currentState!.read());
    } on InputReadException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }
}

// ── Shared result display ─────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final AddVehicleInput result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('brand', result.brand),
            _row('model', result.model),
            _row('year', result.year.toString()),
            _row('fuelType', result.fuelType.name),
            _row('available', result.available.toString()),
            _row('mileage', result.mileage?.toString() ?? '—'),
            _row('notes', result.notes ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
