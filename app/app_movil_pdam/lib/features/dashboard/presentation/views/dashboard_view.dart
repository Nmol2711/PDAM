import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_header.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_hero_card.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_chart_card.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return BlocProvider(
      create: (_) => sl<DashboardCubit>()..loadSummary(),
      child: Scaffold(
        body: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            return SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await context.read<DashboardCubit>().loadSummary();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageFor(ancho),
                    vertical: AppSpacing.page,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DashboardHeader(
                        userName: _getUserName(context),
                        onLogout: () {
                          context.read<AuthBloc>().add(AuthLogoutPressed());
                        },
                      ),
                      const SizedBox(height: AppSpacing.sectionGap),
                      _buildEstado(context, state),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Presenta el estado del cubit: carga, error con reintento o contenido.
  ///
  /// La vista no calcula cifras ni parte de valores prefijados: las del
  /// contenido salen siempre del resumen recibido (RF-7, RF-12).
  Widget _buildEstado(BuildContext context, DashboardState state) {
    if (state is DashboardLoaded) {
      return _buildContenido(context, state);
    }
    if (state is DashboardError) {
      return _PanelError(
        mensaje: state.message,
        onReintentar: () {
          context.read<DashboardCubit>().reintentar();
        },
      );
    }
    return const _PanelCargando();
  }

  Widget _buildContenido(BuildContext context, DashboardLoaded state) {
    final summary = state.summary;
    final hayAvisos =
        summary.isFromCache ||
        summary.calculatedAt == null ||
        state.errorMessage != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hayAvisos) ...[
          _PanelAvisos(summary: summary, errorMessage: state.errorMessage),
          const SizedBox(height: AppSpacing.sectionGap),
        ],

        DashboardHeroCard(
          totalFeedings: summary.pendingFeedings + summary.completedFeedings,
          completedFeedings: summary.completedFeedings,
          pendingFeedings: summary.pendingFeedings,
          onLogsPressed: () {
            context.go('/logs');
          },
        ),
        const SizedBox(height: AppSpacing.sectionGap),

        _buildNutritionEntry(context),
        const SizedBox(height: AppSpacing.sectionGap),

        DashboardMetricsGrid(
          totalPets: summary.totalPets,
          sterilizedPets: summary.sterilizedPets,
          foodDispensedToday: summary.foodDispensedToday,
          foodTargetToday: summary.foodTargetToday,
        ),
        const SizedBox(height: AppSpacing.sectionGap),

        DashboardChartCard(
          weeklyDispensed: summary.weeklyDispensed,
          todayIndex: summary.todayIndex,
        ),
        const SizedBox(height: AppSpacing.sectionGap),

        _buildQuickActions(context),
      ],
    );
  }

  String _getUserName(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return 'Hola, ${authState.user.email.split('@').first}';
    }
    return 'Hola';
  }

  /// Acceso visible a la calculadora nutricional (RF-6).
  ///
  /// La vista solo presenta y navega: el cálculo vive en `NutritionCubit`.
  Widget _buildNutritionEntry(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.primaryContainer,
      borderRadius: AppRadii.cardRadius,
      child: InkWell(
        onTap: () => context.pushNamed('nutrition_calculator'),
        borderRadius: AppRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: AppRadii.controlRadius,
                ),
                child: Icon(
                  Icons.calculate_outlined,
                  color: colors.onPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calculadora Nutricional',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Calcula la ración diaria de tu mascota según WSAVA',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Acciones Rápidas",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                label: 'Nueva Mascota',
                icon: Icons.add_circle_outline,
                color: colors.primary,
                onTap: () {
                  context.push('/create_pet');
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                label: 'Nuevo Horario',
                icon: Icons.schedule_outlined,
                color: colors.primary,
                onTap: () {
                  _showSelectPetDialog(context);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                label: 'Dispositivos',
                icon: Icons.bluetooth_outlined,
                color: colors.primary,
                onTap: () {
                  context.go('/dispensers');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSelectPetDialog(BuildContext context) {
    context.read<PetBloc>().add(PetsLoadedRequested());

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Seleccionar Mascota"),
          content: SizedBox(
            width: double.maxFinite,
            child: BlocBuilder<PetBloc, PetState>(
              builder: (context, state) {
                if (state is PetLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is PetLoaded) {
                  if (state.pets.isEmpty) {
                    return const Text(
                      "No hay mascotas registradas. Registra una mascota primero.",
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.pets.length,
                    itemBuilder: (context, index) {
                      final pet = state.pets[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.pets)),
                        title: Text(pet.name),
                        subtitle: Text(
                          "Especie: ${pet.species.name} • ${pet.weight} kg",
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          context.pushNamed('guided_schedule_form', extra: pet);
                        },
                      );
                    },
                  );
                }
                return const Text("Error al cargar mascotas.");
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancelar"),
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.cardRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppRadii.cardRadius,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de la primera carga del panel.
///
/// No muestra cifras: mientras no hay resumen no existe nada que presentar.
class _PanelCargando extends StatelessWidget {
  const _PanelCargando();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: CircularProgressIndicator(semanticsLabel: 'Cargando panel'),
      ),
    );
  }
}

/// Error sin resumen visible: copy fijo en español y acción de reintento.
class _PanelError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;

  const _PanelError({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: colores.errorContainer,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: colores.onErrorContainer, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: textos.bodyMedium?.copyWith(
              color: colores.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

/// Avisos del resumen visible: respaldo sin conexión y refresco fallido.
class _PanelAvisos extends StatelessWidget {
  final DashboardSummary summary;
  final String? errorMessage;

  const _PanelAvisos({required this.summary, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final avisos = <Widget>[];

    if (summary.isFromCache) {
      final fecha = summary.calculatedAt;
      avisos.add(
        _PanelAviso(
          icono: Icons.cloud_off_outlined,
          titulo: 'Mostrando datos sin conexión',
          detalle: fecha == null
              ? null
              : 'Última actualización: ${_formatearFechaHora(fecha)}',
        ),
      );
    } else if (summary.calculatedAt == null) {
      avisos.add(
        const _PanelAviso(
          icono: Icons.wifi_off_outlined,
          titulo: 'Sin conexión: solo datos locales',
        ),
      );
    }

    if (errorMessage != null) {
      avisos.add(
        _PanelAviso(
          icono: Icons.sync_problem_outlined,
          titulo: errorMessage!,
          detalle: 'Se muestran los últimos datos disponibles.',
          esError: true,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < avisos.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          avisos[i],
        ],
      ],
    );
  }
}

/// Banda de aviso con el color semántico del tema global.
class _PanelAviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? detalle;
  final bool esError;

  const _PanelAviso({
    required this.icono,
    required this.titulo,
    this.detalle,
    this.esError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final fondo = esError ? colores.errorContainer : colores.secondaryContainer;
    final frente = esError
        ? colores.onErrorContainer
        : colores.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: frente, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: textos.bodyMedium?.copyWith(
                    color: frente,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detalle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detalle!,
                    style: textos.bodySmall?.copyWith(color: frente),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formatea el instante del servidor como `dd/MM/yyyy HH:mm`.
///
/// Solo usa los campos de [calculatedAt]; nunca consulta el reloj del
/// dispositivo (RF-6, RF-7).
String _formatearFechaHora(DateTime calculatedAt) {
  String dosDigitos(int valor) => valor.toString().padLeft(2, '0');
  return '${dosDigitos(calculatedAt.day)}/${dosDigitos(calculatedAt.month)}/'
      '${calculatedAt.year} ${dosDigitos(calculatedAt.hour)}:'
      '${dosDigitos(calculatedAt.minute)}';
}
