# Informe — Diagrama de flujo principal del sistema PDAM

## 1. Metadatos

| Campo | Valor |
|---|---|
| Fecha | 2026-10-30 |
| Subsistema | App (Flutter) + Backend (FastAPI) + Firmware (ESP32) |
| Alcance | Diagrama de flujo operativo resumido del sistema |
| Fuente | Código de `app/app_movil_pdam`, `api/app` y `DispensadorESP32/src` |
| Validación | Renderizado sin errores con `@mermaid-js/mermaid-cli` 12.0.0 |

> Diagrama resumido: cada proceso conserva su decisión principal y su validación
> crítica, sin el detalle de cada rama de error.

---

## 2. Diagrama

```mermaid
flowchart TD
  INICIO((Inicio)) --> SESION{"Sesion valida?"}
  SESION -->|No| LOGIN["Registrar cuenta o iniciar sesion"]
  SESION -->|Si| HOME["Pantalla principal"]
  LOGIN -->|Credenciales correctas| HOME

  HOME --> USUARIO
  HOME --> MASCOTAS
  HOME --> DISPENSADORES
  HOME --> HISTORIAL

  subgraph USUARIO["1. Gestion de usuario"]
    direction TB
    U1["Editar correo o contrasena"] --> U2{"Datos validos?"}
    U2 -->|No| U3["Error 400 del catalogo de cuenta"]
    U2 -->|Si| U4["Actualizar cuenta y renovar token si cambia el correo"]
    U5["Eliminar cuenta"] --> U6{"Contrasena correcta?"}
    U6 -->|No| U3
    U6 -->|Si| U7["Borrar cuenta y limpiar datos locales"]
    U7 --> FIN((Fin))
  end

  subgraph MASCOTAS["2. Gestion de mascotas"]
    direction TB
    P1["Crear, editar o eliminar mascota"] --> P2{"Datos validos y sin dispensador vinculado?"}
    P2 -->|No| P3["Error de validacion o 409 pet_has_dispenser"]
    P2 -->|Si| P4["Guardar en servidor y cache Isar"]
    P4 --> P5["Horarios: hora HH:MM y cantidad mayor que 0"]
    P5 --> P6["Generar horarios con calculo WSAVA"]
    P5 --> DISPENSADO
  end

  subgraph DISPENSADORES["3. Gestion de dispensadores"]
    direction TB
    D1["Ver equipo, stock y estado"] --> D2["Activar, desactivar o reabastecer"]
    D2 --> D3{"Cantidad valida y stock hasta 5000 g?"}
    D3 -->|No| D4["Error 400: cantidad_invalida o supera_capacidad"]
    D3 -->|Si| D5["Actualizar estado o stock y registrar el cambio"]
    D1 --> VINCULACION
    D6["Desvincular o reiniciar WiFi"] --> D7["Registrar el cambio"]
    D7 --> BLE
  end

  subgraph VINCULACION["4. Vinculacion dispensador y mascota"]
    direction TB
    V1["Escanear el QR del equipo"] --> V2{"Llave valida, MAC unica y mascota sin dispensador?"}
    V2 -->|No| V3["Error 403, 409 o 400"]
    V2 -->|Si| V4["Crear vinculo 1 a 1 y registro dispenser_linked"]
    V4 --> V5{"Configurar WiFi?"}
    V5 -->|Si| BLE
    V5 -->|No| FIN_V((Fin))
  end

  subgraph BLE["5. Vinculacion de red por Bluetooth"]
    direction TB
    B1["Escanear dispositivos PDAM-Config"] --> B2{"Conexion GATT disponible?"}
    B2 -->|No| B3["Error de conexion BLE"]
    B2 -->|Si| B4["Enviar SSID y contrasena de 2.4 GHz"]
    B4 --> B5{"El ESP32 conecta y el servidor responde?"}
    B5 -->|No| B6["Volver a modo aprovisionamiento"]
    B5 -->|Si| B7["Estado normal: consulta ordenes cada 20 s"]
    B7 --> FIN_B((Fin))
  end

  subgraph HISTORIAL["6. Gestion de logs"]
    direction TB
    L1["Abrir historial"] --> L2{"Filtros y pagina validos?"}
    L2 -->|No| L3["Error 400 del catalogo de logs"]
    L2 -->|Si| L4{"Servidor disponible?"}
    L4 -->|Si| L5["Mostrar respuesta del servidor y cachear en Isar"]
    L4 -->|No| L6["Mostrar cache local con aviso sin conexion"]
  end

  subgraph DISPENSADO["7. Proceso de dispensacion"]
    direction TB
    S1["Barrido cada 30 s encola la comida del horario"] --> S2["ESP32 consulta check-taks cada 20 s"]
    S2 --> S3{"Equipo activo y con orden pendiente?"}
    S3 -->|No| S4["Responder reposo"]
    S3 -->|Si| S5["Dispensar por peso con la celda HX711"]
    S5 --> S6{"Objetivo alcanzado?"}
    S6 -->|Si| S7["Descontar stock medido y registrar exito"]
    S6 -->|No| S8["Registrar fallo sin descontar"]
    S7 --> FIN_D((Fin))
    S8 --> FIN_D
  end
```

---

## 3. Trazabilidad por flujo

| Flujo | Regla principal |
|---|---|
| Usuario | Correo y contraseña válidos, renovación de token al cambiar el correo y baja con contraseña actual |
| Mascotas | Datos válidos, bloqueo del borrado con dispensador vinculado y horarios `HH:MM` con cantidad positiva |
| Dispensadores | Stock entre 0 y 5000 g, reabastecimiento idempotente y registro de cada cambio |
| Vinculación | Llave del QR, MAC única normalizada, relación 1 a 1 y transacción atómica |
| Bluetooth | Conexión GATT, credenciales de red 2.4 GHz y rollback a aprovisionamiento si falla |
| Logs | Filtros y paginación validados, caché local cuando el servidor no responde |
| Dispensación | Orden pendiente, equipo activo, objetivo alcanzado y descuento solo en caso exitoso |

---

## 4. Notas

1. `GET /dispensers/check-taks/{mac}` devuelve hoy una orden fija `serve=true` y `amount=50`; la rama describe la lógica de `order_service.entregar_orden`.
2. Los registros de actividad se escriben en la misma transacción que la operación que los origina.
3. El diagrama se validó con `@mermaid-js/mermaid-cli` 12.0.0 sin errores de sintaxis.
