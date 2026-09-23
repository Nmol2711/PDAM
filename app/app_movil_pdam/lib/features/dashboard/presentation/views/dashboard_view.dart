import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
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
    return BlocProvider(
      create: (_) => sl<DashboardCubit>()..loadSummary(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            int totalPets = 0;
            int sterilizedPets = 0;
            double foodDispensed = 0.0;
            double foodTarget = 300.0;
            int pendingFeedings = 0;
            int completedFeedings = 0;
            List<double> weeklyDispensed = [0, 0, 0, 0, 0, 0, 0];

            if (state is DashboardLoaded) {
              final summary = state.summary;
              totalPets = summary.totalPets;
              sterilizedPets = summary.sterilizedPets;
              foodDispensed = summary.foodDispensedToday;
              foodTarget = summary.foodTargetToday;
              pendingFeedings = summary.pendingFeedings;
              completedFeedings = summary.completedFeedings;
              weeklyDispensed = summary.weeklyDispensed;
            }

            return SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await context.read<DashboardCubit>().loadSummary();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DashboardHeader(
                        userName: _getUserName(context),
                        onThemeToggle: () {
                          context.read<ThemeCubit>().setTheme(
                                Theme.of(context).brightness == Brightness.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              );
                        },
                        onLogout: () {
                          context.read<AuthBloc>().add(AuthLogoutPressed());
                        },
                      ),
                      const SizedBox(height: 24),

                      DashboardHeroCard(
                        totalFeedings: pendingFeedings + completedFeedings,
                        completedFeedings: completedFeedings,
                        pendingFeedings: pendingFeedings,
                        onLogsPressed: () {
                          context.go('/logs');
                        },
                      ),
                      const SizedBox(height: 24),

                      DashboardMetricsGrid(
                        totalPets: totalPets,
                        sterilizedPets: sterilizedPets,
                        foodDispensedToday: foodDispensed,
                        foodTargetToday: foodTarget,
                      ),
                      const SizedBox(height: 24),

                      DashboardChartCard(
                        weeklyDispensed: weeklyDispensed,
                        dailyTarget: foodTarget,
                      ),
                      const SizedBox(height: 24),

                      _buildQuickActions(context),
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

  String _getUserName(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return 'Hola, ${authState.user.email.split('@').first}';
    }
    return 'Hola';
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Acciones Rápidas",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                label: 'Nueva Mascota',
                icon: Icons.add_circle_outline,
                color: const Color(0xFF00C853),
                onTap: () {
                  context.push('/create_pet');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                label: 'Nuevo Horario',
                icon: Icons.schedule_outlined,
                color: const Color(0xFF0066FF),
                onTap: () {
                  _showSelectPetDialog(context);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                label: 'Dispositivos',
                icon: Icons.bluetooth_outlined,
                color: const Color(0xFF6C63FF),
                onTap: () {
                  context.push('/pets');
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
                    return const Text("No hay mascotas registradas. Registra una mascota primero.");
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.pets.length,
                    itemBuilder: (context, index) {
                      final pet = state.pets[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.pets)),
                        title: Text(pet.name),
                        subtitle: Text("Especie: ${pet.species.name} • ${pet.weight} kg"),
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
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
