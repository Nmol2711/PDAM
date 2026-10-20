# Spec 007 — Sistema de Estimación de Alimento Restante (Sin Sensor) y Notificaciones In-App Reutilizables

Estado: borrador

## Contexto y objetivo
Los dispensadores de comida para mascotas (PDAM) no disponen de un sensor físico de peso en el depósito interno para medir el nivel exacto de alimento restante en tiempo real, debido a restricciones de hardware y coste. Para dotar al usuario de visibilidad sobre el estado del alimento sin añadir hardware complejo, se requiere implementar un sistema lógico de estimación de alimento restante basado en el registro manual de reabastecimiento (en gramos o kilogramos hasta un máximo de 5 kg) y el descuento automático por cada dispensación exitosa. Asimismo, se requiere un componente reutilizable de notificaciones *in-app* y una barra de progreso minimalista que alerte cuando el nivel baje del umbral crítico (< 20%), junto con una vista de detalles que calcule las suministraciones restantes basándose en los horarios programados de las mascotas. Todo bajo una arquitectura *Offline-First* con persistencia en Isar y avisos no invasivos de sincronización.

## Usuarios
- **Dueño de mascota / Administrador del dispensador:** Usuario que reabastece el dispositivo, monitorea el nivel de alimento restante, visualiza alertas in-app y consulta el estimado de raciones disponibles.

## Historias de usuario
- HU-1. Como usuario, quiero ingresar la cantidad de alimento reabastecido en gramos o kilogramos (con un límite máximo de 5 kg) para actualizar el stock en el sistema.
- HU-2. Como usuario, quiero visualizar una barra de progreso minimalista y un indicador visual en la tarjeta del dispositivo para conocer rápidamente el nivel de alimento restante.
- HU-3. Como usuario, quiero recibir notificaciones *in-app* reutilizables cuando el nivel de alimento baje del umbral crítico (< 20%) o ante eventos relevantes, sin depender de servicios push externos.
- HU-4. Como usuario, quiero pulsar en "más detalles" para consultar el cálculo aproximado de raciones/suministraciones restantes basadas en los horarios programados de alimentación de las mascotas asociadas.
- HU-5. Como usuario, quiero que el sistema descuente automáticamente el gramaje dispensado del total restante tras cada dispensación exitosa.
- HU-6. Como usuario, quiero que la gestión de alimento funcione de forma *Offline-First* mediante Isar, mostrando un aviso no invasivo cuando los datos procedan de la última sincronización local disponible.

## Definiciones
- **Stock de Alimento:** Cantidad actual estimada de alimento seco en el depósito del dispensador, medida en gramos (g), con un límite máximo de 5,000 g (5 kg).
- **Umbral Crítico:** Nivel de alimento restante inferior al 20% de la capacidad máxima (o del stock máximo configurado/registrado).
- **Notificación In-App Reutilizable:** Componente visual modular dentro de la aplicación móvil para mostrar alertas contextuales sin requerir infraestructura externa de notificaciones push.

## Requisitos funcionales
- RF-1: CUANDO el usuario ingresa una cantidad de alimento al reabastecer el dispensador especificando la unidad (gramos o kilogramos), EL SISTEMA valida y realiza la conversión interna a gramos.
- RF-2: SI la cantidad de alimento ingresada supera los 5,000 gramos (5 kg), ENTONCES EL SISTEMA bloquea el registro y muestra un mensaje de error visual in-app.
- RF-3: CUANDO se registra una cantidad válida de reabastecimiento, EL SISTEMA actualiza el stock actual de alimento en el almacenamiento local Isar y sincroniza con el backend remoto.
- RF-4: CUANDO se procesa una respuesta de dispensación exitosa para el dispositivo, EL SISTEMA descuenta automáticamente del stock restante el gramaje exacto indicado en la orden de dispensación, asegurando que el stock nunca sea inferior a 0 gramos.
- RF-5: MIENTRAS el nivel de alimento restante se encuentre por debajo del umbral crítico del 20%, EL SISTEMA muestra una barra de progreso en estado de advertencia y emite una notificación in-app reutilizable.
- RF-6: EL SISTEMA provee un componente modular reutilizable de notificaciones in-app capaz de mostrar avisos críticos y alertas del sistema en cualquier pantalla de la aplicación móvil.
- RF-7: CUANDO el usuario pulsa en la opción de "más detalles" del dispensador, EL SISTEMA calcula y presenta el número aproximado de raciones/suministraciones restantes basándose en los horarios programados (`schedules`) y porciones asignadas a las mascotas vinculadas.
- RF-8: SI no existe conexión de red al actualizar o consultar el stock de alimento, ENTONCES EL SISTEMA opera bajo la estrategia *Offline-First* utilizando la base de datos local Isar y mostrando un banner o aviso no invasivo indicando que los datos corresponden a la última sincronización.

## Requisitos no funcionales
- RNF-1: **Stack Tecnológico:** FastAPI + SQLite en backend; Flutter + BLoC + GoRouter + Isar en frontend (arquitectura limpia obligatoria).
- RNF-2: **Idioma:** Interfaz de usuario, textos visibles y mensajes en español; código y comentarios técnicos en inglés/formato estándar sin emojis.
- RNF-3: **Privacidad y Dependencias:** Prohibición absoluta de utilizar Firebase Push o SDKs externos de notificaciones; toda alerta es manejada de forma local y *in-app*.
- RNF-4: **Verificabilidad:** Cobertura de pruebas unitarias y de integración para la lógica de cálculo, validación de límites, descuento automático y comportamiento *offline-first*.

## Casos límite
- Ingreso de valores de reabastecimiento negativos o nulos (el sistema debe rechazar y notificar).
- Pérdida de conexión a internet exactamente en el momento de confirmar el reabastecimiento o una dispensación (el cliente Isar actualiza localmente y marca pendiente de sincronización con aviso no invasivo).
- Consumo de alimento que deja el stock en 0 gramos (el sistema acota el valor a 0 y activa la alerta del 100% de vaciado).

## Fuera de alcance
- Falta de un sensor en el depósito interno para medir la cantidad de alimento restante en tiempo real (el sensor HX711 con celda de carga se utilizará en un módulo de hardware futuro exclusivamente para pesar el alimento dispensado).
- Envío de notificaciones push nativas a través de Firebase Cloud Messaging (FCM) u otros servicios en la nube.

## Criterios de finalización
- Pruebas unitarias de backend y frontend pasando al 100% en verde.
- Verificación exitosa de la interfaz en español, respetando la paleta de colores y el tema global de la app.
- Validación del correcto funcionamiento *offline-first* con Isar y el aviso no invasivo de sincronización.

## Dudas abiertas
- Ninguna.
