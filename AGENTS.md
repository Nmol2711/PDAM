# AGENTS.md — PDAM

*(Protoripo dispensador de comida para mascotas.)*

Sistema encargado de dispensadar alimento seco para mascotas (Perros y Gatos). Por medio de un hardware y una aplicacion movil para la gestión de sistema.

**Repositorio:** https://github.com/Nmol2711/PDAM

## Stack y estructura

1. #### BackEnd:

   - Python + FastApi: Creación de la API encarda de la logica de negocio.

   - SQLite : Persistencia de usuarios. Para el desarrollo se usa SQLite para producción migrar a PosgreSQL.

   - Estructura:

     api/
     ├── app/
     │   ├── db/
     │   ├── models/
     │   ├── schemas/
     │   ├── services/
     │   │   └── background_tasks/
     ├── static/
     ├── tests/
     └── venv/

   - Descripción de las carpetas:

     - **`api/`**: Carpeta raíz del proyecto que contiene todo el desarrollo del backend.

     - **`app/`**: Directorio principal donde se aloja el código fuente y la lógica de la aplicación.

     - **`db/`**: Contiene la configuración de la base de datos y la gestión de la conexión.

     - **`models/`**: Define los modelos de datos (por ejemplo, tablas de SQLAlchemy u ORM) para interactuar con la base de datos.

     - **`schemas/`**: Almacena los esquemas de validación de datos (usualmente Pydantic) para estructurar y validar los datos que entran y salen de la API.

     - **`services/`**: Concentra la lógica de negocio principal de la aplicación separada por dominios.

     - **`background_tasks/`**: Subcarpeta destinada a la gestión y ejecución de tareas asíncronas o en segundo plano.

     - **`static/`**: Almacena recursos estáticos (como archivos multimedia, documentos o imágenes) que el servidor procesa o distribuye.

     - **`tests/`**: Contiene las pruebas unitarias y de integración para asegurar el correcto funcionamiento del código.

     - **`venv/`**: Entorno virtual de Python que aísla las dependencias y librerías instaladas para este proyecto en específico.

2. #### FrontEnd

   * Dart + Flutter: Es el fremework seleccionado para el desarrollo de la aplicación móvil.

   * Bloc  + go_router: Manejador de estado y enrutador para la arquitectura móvil.

   * Estructura: 

     lib/
     ├── core/
     │   ├── constant/
     │   ├── di/
     │   ├── error/
     │   ├── network/
     │   ├── offline/
     │   ├── presentation/
     │   ├── router/
     │   ├── services/
     │   └── theme/
     ├── features/
     │   └── <nombre_feature>/
     │       ├── data/
     │       ├── domain/
     │       └── presentation/
     ├── utils/
     └── main.dart

   * Descripción de las carpetas:

     - **`lib/`**: Carpeta principal donde reside todo el código fuente de la aplicación en Flutter.

     - **`core/`**: Contiene elementos transversales y globales que aplican a toda la aplicación.

       - **`constant/`**: Almacena constantes globales (como URLs base, claves o strings fijos).

       - **`di/`** (*Dependency Injection*): Configuración de la inyección de dependencias (ej. con *GetIt* o *Provider*).

       - **`error/`**: Manejo global de excepciones, fallos y errores personalizados.

       - **`network/`**: Clientes HTTP o configuraciones de red (ej. interceptores de *Dio* o *Http*).

       - **`offline/`**: Lógica o almacenamiento local para el funcionamiento sin conexión a internet.

       - **`presentation/`**: Componentes visuales globales y widgets reutilizables en múltiples pantallas.

       - **`router/`**: Configuración de las rutas de navegación de la aplicación.

       - **`services/`**: Servicios globales del sistema (como geolocalización, notificaciones, etc.).

       - **`theme/`**: Definición de estilos visuales, colores, tipografías y gestión del tema (oscuro/claro).

     - **`features/`**: Contiene las diferentes funcionalidades o módulos de la app de forma aislada.

       - **`<nombre_feature>/`**: Carpeta específica para cada módulo funcional de la app (por ejemplo: autenticación, perfil, panel principal).

         - **`data/`**: Capa de datos encargada de consumir APIs, bases de datos locales y modelos de transferencia (*DTOs*).

         - **`domain/`**: Capa de negocio pura que contiene las entidades, casos de uso (*usecases*) y contratos de repositorios.

         - **`presentation/`**: Capa visual de la funcionalidad, que agrupa las pantallas, widgets locales y la gestión de estado (ej. *Bloc*, *Cubit* o *Provider*).

     - **`utils/`**: Funciones de ayuda (*helpers*), extensiones de Dart y formateadores genéricos de uso repetitivo.

     - **`main.dart`**: Archivo principal que inicializa y arranca la aplicación Flutter.

3. #### Hardware:

   - ESP32: Realizar la peticiones a la api y manegar la logica del prototipo.

   - Componentes: ServoMotor MG966R, Aplificador HX711, Celda de carga 5gm.

   - proyecto-esp32/
     ├── include/              # (Opcional en PlatformIO) Archivos de cabecera globales (.h)
     ├── src/                  # Código fuente principal
     │   ├── config/           # Credenciales WiFi, pines GPIO y constantes globales
     │   ├── drivers/          # Capa de hardware (baja abstracción)
     │   ├── services/         # Lógica de negocio y conectividad
     │   ├── tasks/            # Tareas concurrentes (FreeRTOS) o hilos de ejecución
     │   └── main.cpp          # Punto de entrada (inicialización y loop principal)
     ├── lib/                  # Librerías locales o personalizadas del proyecto
     ├── test/                 # Pruebas unitarias para el ESP32
     └── platformio.ini        # Archivo de configuración (si usas PlatformIO / VS Code)

## Arquitecturas

- **Arquitectura Limpia:** La arquitectura de este proyecto siempre será la arquitectura limpia, y aplicando los principios de aislamiento y separación de responsabilidades.

- **Arquitectura Offline-First:** Sincronizar la aplicación para que trabaje con el servidor cuando este responda correctamente. Cuando no haya conexión o el servidor no responda/esté disponible, operar de manera local mediante Isar para garantizar la disponibilidad continua. Apenas se restablezca la comunicación, validar y sincronizar los registros. 

- **Arquitectura de Presentation:**

  ├── presentation/                  # Interfaz visual del proyecto.
  │   ├── bloc/            # Manejador de estados del feature
  │   ├── widgets/       # Componentes aislados reutilizables y que se redibujan
  │  └── views/        # Pantallas completas comformada por los widgets

## Convenciones

- Textos de la interfaz de  la aplicación móvil en español.

- Código simple, nombres descriptivos y comentarios solo donde aporten sin emojis.

- Diseño limpio y responsive; cualquier pantalla nueva debe verse bien en el móvil.

- La aplicación movil debe poder ser capaz funcionar sin conexión al servidor o cuando este no responda.

## Comando

* **Backend (API):**

  - **Iniciar entorno virtual:** `cd api && source venv/bin/activate`
  * **Iniciar servidor:** `cd api && uvicorn app.main:app --reload --port 8000 --host 0.0.0.0`
  * **Correr tests:** `cd api && pytest`

* **Frontend (App Móvil):**

  * **Iniciar aplicación:** `cd app/app_movil_pdam && flutter run --debug --host-vmservice-port=8888`
  * **Correr tests:** `cd app/app_movil_pdam && flutter test`

* **Hardware (ESP32):**

  * **Compilación / Pruebas:** `cd arduino/sketch_jul3a && pio test` (o compilación en Arduino IDE)

## Datos

- flutter_secure_storage: Guardar datos seguros como tokens de seguridad en la aplicación móvil.
- Isar: Paquete de Flutter para guardar datos locales en la aplicación móvil.
- Siempre usar la pleta de colores globales y los themas globales dentro de la app móvil.
- Si dentro de un prompt se proporciona una especificación persistente, limite, o convención, la añades a AGENTS.md y dependiendo de que sea a MEMORY.md

## Forma de trabajar

- Haz solo lo que se pide: no añadas funcionalidades por tu cuenta.

- Cambios pequeños y enfocados; no reescribas lo que ya funciona.

- Si la petición no es clara, hacer la preguntas necesarias para su implementación.

- Al terminar, resume qué has cambiado y cualquier decisión que deba revisar.

## Módulo de Dosificación Nutricional: Restricción de Entradas y Motor de Cálculo

### 1. Variables de Entrada Permitidas (Whitelist)

El sistema debe procesar **únicamente** los siguientes parámetros técnicos y descartar cualquier otra variable accesoria para mantener la estabilidad del módulo funcional:

* **Información del Alimento**: Densidad calórica exacta expresada en **kcal/kg.**
* **Condición Física Corporal (BCS)**: Índice de Condición Corporal (escala numérica).
* **Masa Muscular (MCS)**: Índice de Condición Muscular (Normal, Leve, Moderada o Marcada pérdida).
* **Nivel de Actividad**: Bajo, Medio o Alto.
* **Comidas Diarias**: Frecuencia de alimentación asignada por día.
* **Estatus Reproductivo**: Entero o Castrado/Esterilizado.

---

### 2. Motor de Cálculo Energético y Algoritmo de Dosificación

La prescripción calórica personalizada se rige estrictamente por la siguiente lógica matemática y normativas del documento técnico:

#### A. Requerimiento de Energía en Reposo (RER)

El requerimiento basal se calcula en función del peso corporal (BW en kg). 

* *Nota algorítmica*: Dependiendo de la implementación estándar de la WSAVA, se utiliza la fórmula alométricas estándar o logarítmicas de la tasa metabólica basal.

#### B. Requerimiento de Energía de Mantenimiento (MER)

El MER representa la energía total necesaria e incorpora los factores correctores (etapa de vida, nivel de actividad y estatus reproductivo) multiplicados sobre el RER:
$$\text{MER} = \text{RER} \times \text{Factor Corrector}$$

* *Alerta de Variabilidad Obligatoria*: El sistema debe notificar técnicamente que las necesidades reales de energía pueden variar un **±30% en perros** y un **±50% en gatos**.

#### C. Determinación de la Ración Base Diaria (Gramos)

Se prioriza la medición ponderal (gramos) sobre la volumétrica:
$$\text{Ración Base (g/día)} = \frac{\text{MER (kcal/día)}}{\text{Densidad Calórica (kcal/g)}}$$
*(Si el usuario emplea volumen, se debe estandarizar el uso de una taza de medir estándar de 8-oz o 237 ml)*[cite: 3].

#### D. Lógica de Extras (Premios / Snacks) y Ajuste Nutricional

Para asegurar la integridad de nutrientes esenciales (evitando desequilibrios por alimentos no completos), se aplican los siguientes límites algorítmicos:

1. **Límite de Snacks**: $\text{Snack\_Kcal\_Limit} = \text{MER} \times 0.10$ (Techo máximo del 10%).
2. **Bloqueo / Alerta**: El software debe bloquear o emitir una alerta visual si los extras ingresados por el usuario superan el límite del 10%.
3. **Ajuste de la Ración Principal**: Si se incorporan snacks, la ración principal se recalcula restando el aporte calórico de los mismos:
   $$\text{Final\_Ration\_Kcal} = \text{MER} - \text{User\_Input\_Snack\_Kcal}$$

## Memoria

- Al empezar, lee `MEMORY.md` para conocer el estado del proyecto y las decisiones
  tomadas.
- Al terminar una tarea, actualízalo: estado actual, decisiones importantes (con su
  porqué) y errores a evitar.
- Mantenlo breve (máximo ~50 líneas): resume o elimina lo que ya no aporte.
- Si algo se convierte en una regla permanente, propón moverlo a `AGENTS.md` en lugar de dejarlo en la memoria.
- No guardes nunca datos sensibles (claves, tokens, datos personales).

## Reglas

- Lee `docs/constitution.md` y la spec activa (`specs/NNN-*/`) antes de tocar código.

## Límites

* **✅ Siempre**: 

  * Respetar las reglas, mantener los codigo limpio con comentarios claros.

  * Siempre usar la configuración global de colores y temas para el desarrollo de las pantallas.

  * Seguir la arquitectura limpia para mantener un código escalable.

  * Mantener las views limpias, sin codigo espagueti y conformada solo por widgets/componentes.

  * Siempre: actualizar `MEMORY.md` al terminar cada tarea.

* **⚠️ Pregunta** antes: crear archivos nuevos, cambiar el formato de los datos guardados o añadir dependencias.

* **❌ Nunca**: 

  * Nunca rescribir código funcional o funcionalidades existentes, y de ser obligatorio siempre explicar el porque y preguntar para hacerlo.

  * Nunca usar setState() dentro de un views principales si no es necesario. Siempre se debe hacer dentro del widget especifico.

  * Nunca guardes en el código, API KEY, credenciales, configuraciones, claves secretas. Eso se mueven a la variable de entorno.

## Verificación

- Crear test para cada endpoint, model, services, dependecia o funcionalidad clave del sistema generar desde la aplicacion móvil hasta la api y el prototipo.
- Correr todos los test y asegurarse que pasen correctamente.
- Al implementar un modulo funcional se debe preguntar si la interfaz si funciona correctamente antes de darlo por terminado.
- Al comprobar que todo este bien subir los cambios al repositorio solo si este se a proporcionado o configurado previamente.
