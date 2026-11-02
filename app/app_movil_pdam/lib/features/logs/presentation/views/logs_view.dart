import 'dart:async';

import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:app_movil_pdam/core/presentation/widgets/settings_entry_button.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
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
/// páginas, y no guarda estado de negocio. La recarga manual y la automática
/// (spec 019) se limitan a detectar que la pantalla está visible, emitir la
/// intención y componer el indicador que corresponda.
class LogsView extends StatefulWidget {
  const LogsView({super.key});

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> with WidgetsBindingObserver {
  /// Controlador propio para conservar la posición de la lista al refrescar
  /// (RF-2); se crea una sola vez y no se recrea con cada estado.
  final ScrollController _scrollController = ScrollController();

  /// Suscripción al BLoC mientras dura el gesto de recarga.
  StreamSubscription<LogState>? _suscripcionRefresco;

  /// Futuro pendiente del indicador del gesto, para cerrarlo al desmontar.
  Completer<void>? _completerRefresco;

  /// Último estado de visibilidad de la pestaña según `TickerMode`.
  ///
  /// El shell `StatefulShellRoute.indexedStack` mantiene la rama montada y
  /// desactiva `TickerMode` al ocultarla; la transición de false a true es
  /// «mostrar la pestaña» (RF-2).
  bool _wasVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Carga inicial: catálogo de filtros, primera página y mascotas para el
    // filtro por mascota. No hay estado local de negocio.
    context.read<LogBloc>().add(const LogCatalogRequested());
    context.read<LogBloc>().add(const LogsRequested());
    context.read<PetBloc>().add(PetsLoadedRequested());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_wasVisible) {
      // La pestaña vuelve a estar activa: refresco automático (RF-2).
      _solicitarRefrescoAutomatico();
    }
    _wasVisible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || state != AppLifecycleState.resumed) return;
    // Solo con el historial visible: pestaña activa y sin otra ruta o diálogo
    // por encima (RF-2).
    if (!_wasVisible) return;
    // La ruta de la rama siempre es la actual dentro de su `Navigator`; lo que
    // importa es el navegador raíz, donde caen los diálogos y las pantallas
    // abiertas con `useRootNavigator: true` (RF-2, CP-4).
    if (Navigator.of(context, rootNavigator: true).canPop()) return;
    _solicitarRefrescoAutomatico();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suscripcionRefresco?.cancel();
    // No dejar pendiente el futuro del gesto si la vista se destruye a mitad.
    if (!(_completerRefresco?.isCompleted ?? true)) {
      _completerRefresco!.complete();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _solicitarRefrescoAutomatico() {
    if (!mounted) return;
    context.read<LogBloc>().add(
      const LogRefreshRequested(LogRefreshOrigin.automatico),
    );
  }

  /// Refresco manual del gesto (RF-1).
  ///
  /// El futuro completa cuando el refresco deja de estar en curso o cuando
  /// otra acción lo descarta, para que el indicador del gesto no se quede
  /// animando (RF-4).
  Future<void> _refrescarManualmente() {
    final bloc = context.read<LogBloc>();
    // Ya hay un refresco en curso (normalmente automático) con su propio
    // indicador: el gesto no añade otro ni espera una emisión que el BLoC
    // descarta por concurrencia (RF-4). `refrescoEnCurso` cubre el caso en que
    // una carga de filtro o página ya limpió `state.refresco` pero el refresco
    // anterior sigue pendiente de respuesta.
    if (bloc.state.refresco != null || bloc.refrescoEnCurso) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    _completerRefresco = completer;

    void terminar() {
      if (completer.isCompleted) return;
      completer.complete();
      _suscripcionRefresco?.cancel();
      _suscripcionRefresco = null;
      if (identical(_completerRefresco, completer)) _completerRefresco = null;
    }

    _suscripcionRefresco = bloc.stream.listen((estado) {
      if (!estado.isLoading || estado.refresco != LogRefreshOrigin.manual) {
        terminar();
      }
    });
    bloc.add(const LogRefreshRequested(LogRefreshOrigin.manual));
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de eventos'),
        actions: const <Widget>[
          SettingsEntryButton(ubicacion: UbicacionEntrada.cabeceraPantalla),
        ],
      ),
      body: BlocBuilder<PetBloc, PetState>(
        builder: (context, petState) {
          final pets = petState is PetLoaded ? petState.pets : const <Pet>[];
          return BlocBuilder<LogBloc, LogState>(
            builder: (context, state) {
              final bloc = context.read<LogBloc>();
              // El refresco manual usa solo el indicador del gesto; la barra
              // lineal queda oculta mientras dure (RF-1).
              final mostrarBarraLineal =
                  state.isLoading && state.refresco != LogRefreshOrigin.manual;
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
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _lista(context, state, bloc)),
                        // La barra se superpone a la lista: no inserta ni
                        // desplaza contenido (RF-4).
                        if (mostrarBarraLineal)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
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

    return RefreshIndicator(
      onRefresh: _refrescarManualmente,
      child: ListView(
        controller: _scrollController,
        // El gesto queda disponible aunque la lista esté vacía o no llene la
        // pantalla (RF-1).
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        children: hijos,
      ),
    );
  }
}
