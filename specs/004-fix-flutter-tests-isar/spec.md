# Spec 004 — Corrección de Pruebas y Entorno de Isar en Flutter

Estado: aprobada

## Contexto y objetivo
Al ejecutar las pruebas unitarias e integración en la aplicación Flutter (`flutter test`), el motor de base de datos local Isar falla al no encontrar el binario nativo `libisar.so` en el directorio de ejecución de pruebas. Adicionalmente, el archivo `pubspec.yaml` declara una carpeta de activos `assets/icos/` que no existe en el sistema de ficheros, generando advertencias y errores de carga de activos durante el análisis y compilación.
El objetivo de esta especificación es definir los requisitos para solucionar la inicialización de Isar en pruebas (permitiendo la descarga o carga correcta del binario nativo), corregir los activos declarados en `pubspec.yaml`, y garantizar que el 100% de las pruebas automatizadas de Flutter pasen correctamente sin romper la arquitectura offline-first ni el código de producción.

## Usuarios
* **Desarrollador / QA:** Necesita ejecutar `flutter test` con éxito y sin errores de binarios nativos ni activos faltantes para verificar la integridad del sistema frontend.

## Historias de usuario
* **HU-1:** Como desarrollador, quiero que las pruebas unitarias que utilizan Isar inicialicen correctamente el núcleo nativo descargando o referenciando `libisar.so`, para que los tests de datasources locales y repositorios pasen con éxito.
* **HU-2:** Como desarrollador, quiero que la configuración de activos en `pubspec.yaml` refleje únicamente directorios existentes, evitando advertencias de compilación y test.

## Requisitos funcionales (EARS)
* **RF-01 (Inicialización de Isar Core en Tests):** CUANDO se ejecuten pruebas unitarias que requieran Isar (`Isar.initializeIsarCore()`), EL SISTEMA debe configurar la descarga o carga automática del binario nativo (`libisar.so` / `libisar.dylib` / `isar.dll`) según la plataforma de ejecución.
* **RF-02 (Corrección de Activos en Pubspec):** CUANDO la aplicación compile o ejecute tests, EL SISTEMA debe cargar únicamente directorios de activos válidos y existentes, eliminando referencias a rutas inexistentes como `assets/icos/`.

## Requisitos no funcionales
* **RNF-01:** La solución no debe modificar la lógica de producción de Isar ni alterar el comportamiento offline-first de la aplicación en dispositivos reales.
* **RNF-02:** Los tests automatizados de Flutter (`flutter test`) deben completarse sin errores de carga de bibliotecas dinámicas.

## Casos límite
* **CL-1 (Entorno CI / Sin conexión):** Si se ejecuta en un entorno sin conexión a internet, la inicialización de Isar en tests debe manejar la ausencia de descarga o utilizar un binario cacheado de manera robusta.

## Fuera de alcance
* Cambios en la versión de Isar o en los esquemas de base de datos.
* Modificaciones al backend FastAPI o al firmware ESP32.

## Criterios de finalización
* Todos los tests en `app/app_movil_pdam/test/` pasan correctamente al ejecutar `flutter test`.
* No se reportan errores de bibliotecas dinámicas faltantes ni advertencias de activos inexistentes.
