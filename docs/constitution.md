# Constitución de PDAM

Principios innegociables. Toda spec, plan y tarea debe cumplirlos.

1. **Stack Tecnológico:** FastAPI + SQLite (Backend), Flutter + BLoC + GoRouter + Isar (Frontend Offline-First) y ESP32 (Hardware).
2. **Relación Spec-Código:** Trazabilidad estricta bajo el Modelo en V; cada requerimiento se valida con su respectiva prueba y componente.
3. **Separación Lógica-Interfaz:** Clean Architecture absoluta; lógica de negocio en dominio/servicios y cero lógica en vistas principales de Flutter.
4. **Política de Tests:** Cobertura obligatoria de pruebas unitarias e integración en todos los módulos (API, app y hardware) antes de fusionar.
5. **Protección de Datos:** Cifrado seguro de credenciales con `flutter_secure_storage` y prohibición estricta de hardcodear datos sensibles.
6. **Idioma:** Interfaz de usuario, textos visibles y documentación en español; código, nombres y comentarios técnicos en formato estándar.
