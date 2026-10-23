# Plan 012 — Stock del dispensador en tiempo real y limpieza de la tarjeta

Incluye la revisión de reabastecimiento offline y validación de capacidad.

## 1. Archivos y responsabilidades

### Backend (FastAPI)
- **`api/app/services/dispenser_service.py`**: `refill_dispenser` valida que
  `stock_actual + grams` no supere 5000 g. Si lo supera responde 400 con
  `detail={"code": "refill_exceeds_capacity", "message": "El reabastecimiento
  supera el límite de 5 kg"}` y no modifica ni confirma la fila. Cubre RF-7,
  RF-8.
- **`api/tests/test_dispenser_food.py`**: suma válida, límite exacto, rechazo
  por exceso, kg→g, cantidad inválida y dispensador inexistente.

### Frontend (Flutter)
- **`lib/features/dispenser/domain/entity/dispenser_food_status.dart`**:
  `RefillLimitException`; `convertAndValidateRefill` y `applyRefill` rechazan
  cantidades inválidas o sumas mayores a 5000 g; se conservan los formateadores
  g/kg. Cubre RF-3, RF-7, RF-8, RF-13.
- **`lib/features/dispenser/domain/entity/dispenser.dart`**: nuevo
  `pendingRefillGrams` con default 0, incluido en `props` y `copyWith`.
- **`lib/core/offline/models/local_dispenser.dart`** y `local_dispenser.g.dart`:
  campo persistente `pendingRefillGrams`; regenerar con `build_runner`.
- **`lib/features/dispenser/data/models/dispenser_model.dart`**: mapea el
  pendiente entre HTTP, Isar y dominio.
- **`lib/features/dispenser/data/datasource/local/local_dispenser_datasource.dart`**:
  `saveLocalDispenser` acepta `pendingRefillGrams`; `null` conserva el valor
  existente y `0` lo limpia. Mantiene `getRemoteIdByDeviceId`.
- **`lib/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart`**:
  `refillDispenser` traduce el `detail` con código a `ApiException`.
- **`lib/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart`**:
  `refillFood` valida con el stock local, aplica offline y encola el delta, o
  envía `pendiente + nuevo` al servidor; `refreshDispensers` envía pendientes
  antes de consultar y reconcilia si el servidor rechaza por límite. Cubre RF-4,
  RF-5, RF-6, RF-7, RF-8, RF-10, RF-11, RF-12.
- **`lib/features/dispenser/domain/repository/dispenser_repositories.dart`**:
  mantiene `refreshDispensers()` y `refillFood()`.
- **`lib/features/dispenser/presentation/bloc/dispenser_state.dart`**:
  `refillSuccess` y `refillLimitExceeded` en `DispenserListLoaded`.
- **`lib/features/dispenser/presentation/bloc/dispenser_bloc.dart`**:
  `RefillLimitException` emite la lista con `refillLimitExceeded`; el éxito
  (online u offline) emite `refillSuccess`; no emite `DispenserErrorState` por
  reabastecimiento.
- **`lib/features/dispenser/presentation/views/dispensers_page.dart`**:
  `Timer.periodic(5 s)`, `WidgetsBindingObserver`, `RefreshIndicator`, avisos de
  límite y de éxito. Cubre RF-4, RF-5, RF-6, RNF-1, RNF-2, RF-13.
- **`lib/features/dispenser/presentation/widgets/device_card_widget.dart`**:
  valida la suma con el stock actual antes de enviar; muestra el mensaje de
  límite dentro del diálogo; actualiza la nota de capacidad y el texto de éxito.
  Cubre RF-1, RF-2, RF-8, RF-13.
- **`lib/features/dispenser/presentation/widgets/dispenser_food_progress_bar.dart`**:
  muestra gramos, kilogramos y porcentaje. Cubre RF-3.
- **`lib/features/dispenser/presentation/views/ble_scan_page.dart`**:
  al cerrarse recarga la lista. Cubre RF-9.

### Pruebas
- `test/features/dispenser/presentation/views/dispensers_page_test.dart`
- `test/features/dispenser/presentation/views/wifi_provisioning_page_test.dart`
- `test/features/dispenser/presentation/bloc/dispenser_bloc_test.dart`
- `test/features/dispenser/data/repositories/dispenser_repository_impl_test.dart`
- `test/features/dispenser/data/datasource/local/local_dispenser_datasource_test.dart`
- `test/features/dispenser/domain/dispenser_food_status_test.dart`
- `test/features/dispenser/data/models/dispenser_model_test.dart` (si existe)
- `test/features/dispenser/presentation/views/register_dispenser_view_test.dart`

## 2. Algoritmo

### Refresco
```
refreshDispensers():
  si no hay conexión: salir
  para cada dispensador local con petId:
    remoteId = resolver id remoto
    si pendingRefillGrams > 0:
      si remoteId == null: continuar (no se puede sincronizar)
      intentar POST /dispensers/{remoteId}/refill {amount: pending, unit: "g"}
        éxito: cachear respuesta y limpiar pendiente
        límite: GET /dispensers/{petId}, cachear y limpiar pendiente
        otro fallo: conservar pendiente y stock local; continuar
      continuar
    intentar GET /dispensers/{petId} y cachear (preserva pendiente 0)
    si falla: conservar el local
```

### Reabastecimiento
```
refillFood(dispenserId, grams):
  local = buscar por deviceId
  si no existe: fallo interno
  nuevoStock = applyRefill(local.currentFoodGrams, grams)   // rechaza >5000
  delta = local.pendingRefillGrams + grams
  si no hay conexión o no hay remoteId:
    guardar stock local + delta pendiente; terminar (éxito)
  intentar POST refill(remoteId, delta)
    éxito: cachear respuesta y limpiar pendiente
    código refill_exceeds_capacity: lanzar RefillLimitException
    otro fallo: guardar stock local + delta pendiente; terminar (éxito)
```

### Servidor
```
grams = kg→g
si grams <= 0 o stock + grams > 5000:
  400 refill_exceeds_capacity
current_food_grams = stock + grams
```

### Avisos
- Límite: `El reabastecimiento supera el límite de 5 kg` (inline en el diálogo y
  SnackBar si el rechazo ocurre en el servidor).
- Éxito: `Reabastecimiento con éxito`.

## 3. Decisiones y alternativas descartadas
- **Rechazar el exceso (elegido):** evita el recorte silencioso y advierte al
  usuario. Se descarta aplicar hasta 5000 g porque confunde la cantidad real.
- **Cola offline en Isar (elegido):** el delta pendiente sobrevive al cierre de
  la app y se envía en el siguiente refresco. Se descarta una cola en memoria
  (se perdería) y almacenamiento seguro (no es el almacén offline del proyecto).
- **Servidor autoritativo al sincronizar (elegido):** si el stock real no admite
  el delta, se reconcilia con el servidor y se limpia el pendiente. Se descarta
  reintentar indefinidamente un delta imposible.
- **Sondeo cada 5 s (elegido):** sin dependencias nuevas; el pendiente se envía
  en el siguiente refresco visible, pull-to-refresh o retorno a primer plano.
- **No descontar en la app (elegido):** el servidor ya descuenta; descontar en el
  cliente duplicaría el descuento.
- **Mensajes solo límite/éxito (elegido):** cualquier fallo no-límite se trata
  como offline y se encola; no se muestran errores técnicos.

## 4. Estrategia de pruebas
- Backend: suma, límite exacto, rechazo, kg→g, valores inválidos y 404.
- Dominio: `applyRefill` rechaza, acepta el límite exacto y suma normal;
  `convertAndValidateRefill` usa el mensaje de límite.
- Isar: guarda, conserva y limpia `pendingRefillGrams`; reapertura de la base.
- Repositorio: refill offline válido/excedido; online con pendiente; límite del
  servidor; fallo de red; refresco con pendiente y reconciliación.
- BLoC: éxito online/offline; límite sin error genérico.
- Widgets: límite inline en el diálogo; aviso de límite desde el BLoC; texto de
  éxito; barra con ambas unidades; tarjeta limpia.
