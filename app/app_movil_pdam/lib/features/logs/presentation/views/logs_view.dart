import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_filters_bar.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_item_widget.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_notice_widget.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_pagination_bar.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Pantalla del historial de actividad (RF-33).
///
/// Solo compone widgets y emite eventos: no calcula zonas horarias, totales ni
/// páginas, y no guarda estado de negocio.
class LogsView extends StatefulWidget {
  const LogsView({super.key});

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  @override
  void initState() {
    super.initState();
    // Carga inicial: catálogo de filtros, primera página y mascotas para el
    // filtro por mascota. No hay estado local de negocio.
    context.read<LogBloc>().add(const LogCatalogRequested());
    context.read<LogBloc>().add(const LogsRequested());
    context.read<PetBloc>().add(PetsLoadedRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de eventos'), elevation: 0),
      body: BlocBuilder<PetBloc, PetState>(
        builder: (context, petState) {
          final pets = petState is PetLoaded ? petState.pets : const <Pet>[];
          return BlocBuilder<LogBloc, LogState>(
            builder: (context, state) {
              final bloc = context.read<LogBloc>();
              return Column(
                children: [
                  LogFiltersBar(
                    filters: state.filters,
                    catalog: state.catalog,
                    pets: pets,
                    onFiltersChanged: (filters) =>
                        bloc.add(LogFiltersChanged(filters)),
                    onClear: () => bloc.add(const LogFiltersCleared()),
                  ),
                  Expanded(child: _lista(context, state, bloc)),
                  LogPaginationBar(
                    page: state.page,
                    totalPages: state.totalPages,
                    total: state.total,
                    onPrevious: state.page > 1 && !state.isLoading
                        ? () => bloc.add(LogPageRequested(state.page - 1))
                        : null,
                    onNext: state.page < state.totalPages && !state.isLoading
                        ? () => bloc.add(LogPageRequested(state.page + 1))
                        : null,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _lista(BuildContext context, LogState state, LogBloc bloc) {
    final hijos = <Widget>[
      if (state.isLoading) const LinearProgressIndicator(),
      if (state.errorMessage != null)
        LogNoticeWidget.error(
          message: state.errorMessage!,
          onRetry: () => bloc.add(const LogRetryRequested()),
        )
      else if (state.isOffline)
        LogNoticeWidget.offline(sinDatosLocales: state.items.isEmpty),
      if (state.errorMessage == null &&
          state.items.isEmpty &&
          !state.isLoading &&
          // Sin la primera consulta terminada no se anuncia un vacío que aún
          // no se ha comprobado (RF-33).
          state.hasLoaded)
        const LogNoticeWidget.empty(),
      ...state.items.map((log) => LogItemWidget(log: log)),
    ];

    return ListView(padding: const EdgeInsets.only(bottom: 8), children: hijos);
  }
}
