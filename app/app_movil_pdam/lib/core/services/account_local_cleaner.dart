import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:isar/isar.dart';

/// Paso de la limpieza local de la baja. Se usa para distinguir con precisión
/// qué parte terminó y cuál falló, sin exponer mensajes técnicos (RNF-10).
enum AccountCleanupStep {
  marca,
  token,
  credenciales,
  perfil,
  mascotas,
  dispensadores,
  horarios,
  historial,
  borrarMarca,
}

/// Resultado verificable de la limpieza local de la baja (RNF-10).
///
/// [exitoso] solo es verdadero cuando todos los pasos terminaron. Si algo
/// falla, [pasoFallido] identifica el primer paso que no se completó y
/// [pasosCompletados] conserva el avance real.
class AccountCleanupResult {
  final bool exitoso;
  final AccountCleanupStep? pasoFallido;
  final List<AccountCleanupStep> pasosCompletados;

  const AccountCleanupResult.exito({required this.pasosCompletados})
    : exitoso = true,
      pasoFallido = null;

  const AccountCleanupResult.fallo({
    required this.pasoFallido,
    required this.pasosCompletados,
  }) : exitoso = false;
}

/// Limpieza local de la baja con marca persistente (RF-18, RNF-10).
///
/// Orden obligatorio: escribe la marca, borra token y tipo, credenciales
/// cifradas, perfil cacheado y las colecciones de la cuenta en Isar, y solo
/// entonces borra la marca. Nunca toca `user_theme_mode`: la apariencia
/// pertenece al dispositivo y sobrevive a la baja (RF-23).
abstract class AccountLocalCleaner {
  /// Ejecuta la limpieza completa de la baja. Si [correo] es nulo, la clave de
  /// la cuenta se obtiene del perfil cacheado.
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo});

  /// Reintenta la limpieza si existe la marca de baja pendiente. Se invoca
  /// antes de `runApp` para completar una limpieza interrumpida (RNF-10).
  /// Devuelve `null` cuando no había nada pendiente.
  Future<AccountCleanupResult?> limpiarSiPendiente();

  /// Limpia la sesión cuando el servidor rechaza el token con 401 (RF-19).
  ///
  /// Borra exactamente lo que permitiría volver a entrar sin conexión con una
  /// cuenta que ya no existe: token, tipo de token, credenciales cifradas y
  /// perfil cacheado. No escribe la marca de baja pendiente (esa marca es solo
  /// de la baja, RNF-10), no toca las colecciones de Isar —mascotas, horarios e
  /// historial se conservan para resincronizarlos— y respeta `user_theme_mode`
  /// (RF-23). Cada paso es independiente: un fallo de almacenamiento no impide
  /// borrar el resto ni cerrar la sesión.
  Future<void> limpiarPorSesionExpirada();
}

class AccountLocalCleanerImpl implements AccountLocalCleaner {
  /// Clave histórica con la que los datasources locales guardan las filas de la
  /// cuenta actual. Se limpia junto con el correo normalizado real.
  static const String _claveLocalLegado = 'default_user';

  final PendingDeletionStore _pendingDeletionStore;
  final AuthLocalDatasource _authLocalDatasource;
  final LocalProfileDatasource _localProfileDatasource;
  final Future<Isar> Function() _abrirIsar;

  AccountLocalCleanerImpl({
    required PendingDeletionStore pendingDeletionStore,
    required AuthLocalDatasource authLocalDatasource,
    required LocalProfileDatasource localProfileDatasource,
    Future<Isar> Function()? abrirIsar,
  }) : _pendingDeletionStore = pendingDeletionStore,
       _authLocalDatasource = authLocalDatasource,
       _localProfileDatasource = localProfileDatasource,
       _abrirIsar = abrirIsar ?? IsarService.init;

  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async {
    final completados = <AccountCleanupStep>[];

    // 1. Marca antes de cualquier borrado. Si no se puede escribir, no se toca
    // nada: sin marca no habría forma de reintentar ni de bloquear el acceso.
    try {
      await _pendingDeletionStore.markPending();
      completados.add(AccountCleanupStep.marca);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.marca,
        pasosCompletados: completados,
      );
    }

    // 2. Token de sesión y su tipo.
    try {
      await _authLocalDatasource.deleteToken();
      completados.add(AccountCleanupStep.token);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.token,
        pasosCompletados: completados,
      );
    }

    // 3. Credenciales cifradas del acceso sin conexión.
    try {
      await _authLocalDatasource.clearCachedCredentials();
      completados.add(AccountCleanupStep.credenciales);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.credenciales,
        pasosCompletados: completados,
      );
    }

    // 4. Perfil cacheado. La clave se toma del correo recibido o del propio
    // perfil guardado, de modo que también sirve al reintentar tras reiniciar.
    var clave = correo == null ? null : _normalizar(correo);
    try {
      final perfil = await _localProfileDatasource.getCachedProfile();
      if (perfil != null) {
        clave ??= _normalizar(perfil.email);
        await _localProfileDatasource.deleteProfile(perfil.email);
      }
      completados.add(AccountCleanupStep.perfil);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.perfil,
        pasosCompletados: completados,
      );
    }

    // 5. Colecciones Isar de la cuenta. Una sola transacción: o se borran las
    // filas de la cuenta o no se borra ninguna (RNF-10).
    final claves = _clavesDeCuenta(clave);
    var pasoActual = AccountCleanupStep.dispensadores;
    try {
      final isar = await _abrirIsar();
      await isar.writeTxn(() async {
        // Los dispensadores se resuelven antes de borrar sus mascotas porque su
        // pertenencia se deduce de `petRemoteId`.
        pasoActual = AccountCleanupStep.dispensadores;
        await _borrarDispensers(isar, claves);

        pasoActual = AccountCleanupStep.mascotas;
        await _borrarPets(isar, claves);

        pasoActual = AccountCleanupStep.horarios;
        await _borrarSchedules(isar, claves);

        pasoActual = AccountCleanupStep.historial;
        await _borrarLogs(isar, claves);
      });
      completados.addAll(<AccountCleanupStep>[
        AccountCleanupStep.mascotas,
        AccountCleanupStep.dispensadores,
        AccountCleanupStep.horarios,
        AccountCleanupStep.historial,
      ]);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: pasoActual,
        pasosCompletados: completados,
      );
    }

    // 6. La marca solo desaparece cuando la limpieza terminó completa.
    try {
      await _pendingDeletionStore.clear();
      completados.add(AccountCleanupStep.borrarMarca);
    } catch (_) {
      return AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.borrarMarca,
        pasosCompletados: completados,
      );
    }

    return AccountCleanupResult.exito(pasosCompletados: completados);
  }

  @override
  Future<void> limpiarPorSesionExpirada() async {
    // Token de sesión y su tipo: sin ellos no hay petición autenticada.
    try {
      await _authLocalDatasource.deleteToken();
    } catch (_) {
      // Se intenta el resto igualmente: cerrar la sesión no puede depender de
      // un almacenamiento que no responde.
    }

    // Credenciales cifradas del acceso sin conexión (RF-19).
    try {
      await _authLocalDatasource.clearCachedCredentials();
    } catch (_) {
      // Igual que arriba: el perfil y el cierre de sesión siguen adelante.
    }

    // Perfil cacheado real. Sin él, el arranque sin conexión no puede mostrar
    // datos de una cuenta que ya no existe (RF-07).
    try {
      final perfil = await _localProfileDatasource.getCachedProfile();
      if (perfil != null) {
        await _localProfileDatasource.deleteProfile(perfil.email);
      }
    } catch (_) {
      // La limpieza es de mejor esfuerzo: no se propaga el fallo al estado.
    }
  }

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async {
    if (!await _pendingDeletionStore.isPending()) return null;
    return limpiarTrasBaja();
  }

  /// Misma forma canónica que el dominio de la cuenta: sin espacios exteriores
  /// y en minúsculas. No se importa el dominio para no invertir la dependencia
  /// de `core` hacia una feature.
  String _normalizar(String texto) => texto.trim().toLowerCase();

  /// Claves con las que los datasources locales guardan filas de la cuenta.
  ///
  /// `default_user` es la clave heredada que usan hoy mascotas, horarios e
  /// historial; el correo normalizado cubre las filas que se guarden por
  /// cuenta. Al reintentar en el arranque el perfil ya no existe y [clave] es
  /// nula: se limpia igualmente la clave heredada, que es la que contiene las
  /// filas reales, sin barrer filas de otra cuenta.
  Set<String> _clavesDeCuenta(String? clave) => <String>{
    _claveLocalLegado,
    ?clave,
  };

  /// Borra los dispensadores que pertenecen a la cuenta.
  ///
  /// `LocalDispenser` no guarda propietario: la pertenencia se deduce de la
  /// mascota vinculada. Se borran los vinculados a mascotas de la cuenta y los
  /// que todavía no tienen mascota, que son filas de este dispositivo de una
  /// sola cuenta; los vinculados a mascotas de otra cuenta se conservan.
  Future<void> _borrarDispensers(Isar isar, Set<String> claves) async {
    final idsMascotas = <int>{};
    for (final clave in claves) {
      final mascotas = await isar.localPets
          .filter()
          .userIdEqualTo(clave)
          .findAll();
      idsMascotas.addAll(
        mascotas.map((mascota) => mascota.remoteId).whereType<int>(),
      );
    }

    final dispensadores = await isar.localDispensers.where().findAll();
    final sobrantes = dispensadores
        .where(
          (dispensador) =>
              dispensador.petRemoteId == null ||
              idsMascotas.contains(dispensador.petRemoteId),
        )
        .map((dispensador) => dispensador.id)
        .toList();
    if (sobrantes.isNotEmpty) {
      await isar.localDispensers.deleteAll(sobrantes);
    }
  }

  Future<void> _borrarPets(Isar isar, Set<String> claves) async {
    for (final clave in claves) {
      await isar.localPets.filter().userIdEqualTo(clave).deleteAll();
    }
  }

  Future<void> _borrarSchedules(Isar isar, Set<String> claves) async {
    for (final clave in claves) {
      await isar.localSchedules.filter().userIdEqualTo(clave).deleteAll();
    }
  }

  Future<void> _borrarLogs(Isar isar, Set<String> claves) async {
    for (final clave in claves) {
      await isar.localLogs.filter().userIdEqualTo(clave).deleteAll();
    }
  }
}
