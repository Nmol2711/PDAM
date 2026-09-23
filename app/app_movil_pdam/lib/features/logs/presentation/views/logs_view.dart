import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_item_widget.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class LogsView extends StatefulWidget {
  const LogsView({super.key});

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  int? _selectedPetId;
  String? _selectedDate; // YYYY-MM-DD

  @override
  void initState() {
    super.initState();
    context.read<LogBloc>().add(const LogsRequested());
    context.read<PetBloc>().add(PetsLoadedRequested());
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = "${picked.toLocal()}".split(' ')[0];
      });
      _fetchLogs();
    }
  }

  void _fetchLogs() {
    context.read<LogBloc>().add(
          LogsRequested(petId: _selectedPetId, date: _selectedDate),
        );
  }

  void _clearFilters() {
    setState(() {
      _selectedPetId = null;
      _selectedDate = null;
    });
    _fetchLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Eventos'),
        elevation: 0,
        actions: [
          if (_selectedPetId != null || _selectedDate != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Limpiar filtros',
              onPressed: _clearFilters,
            ),
        ],
      ),
      body: Column(
        children: [
          // --- BARRA DE FILTROS ---
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                // Filtro por Mascota
                Expanded(
                  child: BlocBuilder<PetBloc, PetState>(
                    builder: (context, state) {
                      List pets = [];
                      if (state is PetLoaded) {
                        pets = state.pets;
                      }

                      final effectiveValue = pets.any((p) => p.id == _selectedPetId) ? _selectedPetId : null;

                      return DropdownButtonFormField<int?>(
                        value: effectiveValue,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Mascota',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todas las mascotas', overflow: TextOverflow.ellipsis)),
                          ...pets.map((pet) => DropdownMenuItem(
                                value: pet.id,
                                child: Text(pet.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedPetId = val;
                          });
                          _fetchLogs();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // Filtro por Fecha
                OutlinedButton.icon(
                  onPressed: () => _selectDate(context),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_selectedDate ?? 'Fecha'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // --- LISTA DE LOGS ---
          Expanded(
            child: BlocConsumer<LogBloc, LogState>(
              listener: (context, state) {
                if (state is LogLoaded && state.isOffline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Los registros se reflejarán cuando haya conexión con el servidor'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is LogLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is LogError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(state.message, style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                if (state is LogLoaded) {
                  if (state.logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_note, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No hay eventos registrados',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.logs.length,
                    itemBuilder: (context, index) {
                      return LogItemWidget(log: state.logs[index]);
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
