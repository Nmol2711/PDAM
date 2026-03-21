# PDAM - Flutter Mobile Application 📱

This is the mobile frontend for the **PDAM** (Automated Pet Food Dispenser) system. Built with **Flutter**, this app allows users to manage and monitor their pet's feeding schedules in real-time.

---

## 🇺🇸 English Version

### 🏗️ Architecture & State Management
This application is built following **Clean Architecture** principles to ensure a decoupled, testable, and scalable codebase:
* **Data Layer:** Handles API calls (FastAPI) and local storage.
* **Domain Layer:** Contains business logic, entities, and use cases.
* **Presentation Layer:** Managed using the **BLoC/Cubit** pattern for a predictable state.

### ✨ Features
* **Real-time Monitoring:** View the dispenser status instantly.
* **Custom Scheduling:** Set feeding times directly from the phone.
* **Secure Auth:** Multi-user authentication system.
* **Responsive UI:** Optimized for various screen sizes and dark/light modes.

---

## 🇪🇸 Versión en Español

### 🏗️ Arquitectura y Gestión de Estado
Esta aplicación está construida siguiendo los principios de **Arquitectura Limpia** para garantizar un código desacoplado, testeable y escalable:
* **Capa de Datos (Data):** Maneja las llamadas a la API (FastAPI) y el almacenamiento local.
* **Capa de Dominio (Domain):** Contiene la lógica de negocio, entidades y casos de uso.
* **Capa de Presentación (Presentation):** Gestionada con el patrón **BLoC/Cubit** para un estado predecible.

### ✨ Características
* **Monitoreo en Tiempo Real:** Visualiza el estado del dispensador al instante.
* **Programación Personalizada:** Configura horarios de alimentación desde el móvil.
* **Autenticación Segura:** Sistema de inicio de sesión multiusuario.
* **Interfaz Adaptativa:** Optimizada para diferentes tamaños de pantalla y modo claro/oscuro.

---

### 🚀 Getting Started / Primeros Pasos
1. **Clone the repo:** `git clone https://github.com/Nmol2711/PDAM.git`
2. **Install dependencies:** `flutter pub get`
3. **Configure API:** Ensure the FastAPI backend is running and update the base URL in the app's configuration.
4. **Run the app:** `flutter run`