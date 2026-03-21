---

## 🇺🇸 English Version

# PDAM - Automatic Pet Food Dispenser Prototype

This project is a comprehensive system designed to automate and monitor pet feeding. Developed as part of the Systems Engineering program at the Universidad Politécnica Territorial José Félix Ribas.

### 🚀 Technologies Used

The PDAM ecosystem is divided into three main components:
* **Frontend (Mobile App):** Developed with **Flutter & Dart**, implementing **Clean Architecture** and the **BLoC** design pattern for robust state management.
* **Backend (API):** Built with **FastAPI (Python)**, responsible for business logic, data persistence, and hardware communication.
* **Hardware:** Controlled via **Arduino**, in charge of the physical dispenser activation and level sensors.

### 🏗️ Mobile Application Architecture

The app follows Clean Architecture principles to ensure scalability and ease of maintenance:
* **Data:** Implementation of repositories, models, and data sources (Remote & Local).
* **Domain:** Pure business entities and use cases.
* **Presentation:** Responsive UI with dark/light mode support and state management with BLoC/Cubit.

### 📋 Main Features
* **Authentication:** Secure login system for users.
* **Dashboard:** Real-time monitoring of the dispenser status.
* **Scheduling:** Configuration of specific schedules for feeding.
* **History (Logs):** Detailed record of every meal served.
* **Responsive Interface:** Adapted for mobile devices, tablets, and desktops.

### 🛠️ Installation and Setup

#### 🐍 Backend (API)
1. **Environment Setup:** Create a `.env` file in the `api/` folder and define the variables for `SECRET_KEY` and `DATABASE_URL`.
2. **Dependencies:** Run `pip install -r requirements.txt`.

#### 📱 Frontend (Mobile App)
1. **Packages:** Run `flutter pub get` to download dependencies.
2. **Run:** Execute `flutter run` on your connected device.

**Author:** Nelson - Systems & Informatics Engineering Student.


# PDAM - Prototipo de Dispensador Automático de Alimento para Mascotas (Es)

Este proyecto es un sistema integral diseñado para automatizar y monitorear la alimentación de mascotas. Desarrollado como parte de la formación en Ingeniería de Sistemas en la Universidad Politécnica Territorial José Félix Ribas.

## 🚀 Tecnologías Utilizadas

El ecosistema PDAM está dividido en tres componentes principales:

* **Frontend (App Móvil):** Desarrollado con **Flutter** y **Dart**, implementando **Clean Architecture** y el patrón de diseño **BloC** para una gestión de estado robusta.
* **Backend (API):** Construido con **FastAPI** (Python), encargado de la lógica de negocio, persistencia de datos y comunicación con el hardware.
* **Hardware:** Controlado mediante **Arduino**, encargado de la activación física del dispensador y sensores de nivel.

## 🏗️ Arquitectura de la Aplicación Móvil

La aplicación sigue los principios de Clean Architecture para garantizar escalabilidad y facilidad de mantenimiento:

* **Data:** Implementación de repositorios, modelos y fuentes de datos (Remote & Local).
* **Domain:** Entidades de negocio y casos de uso puros.
* **Presentation:** UI responsive con soporte para modo oscuro/claro y gestión de estado con BloC/Cubit.

## 📋 Características Principales

* **Autenticación:** Sistema de login seguro para usuarios.
* **Dashboard:** Monitoreo en tiempo real del estado del dispensador.
* **Programación:** Configuración de horarios específicos para la alimentación.
* **Historial (Logs):** Registro detallado de cada comida servida.
* **Interfaz Responsive:** Adaptada para dispositivos móviles, tablets y escritorio.

## 🛠️ Instalación y Configuración

### 🐍 Backend (API)

1.  **Configuración de Entorno:**
    Crea un archivo llamado `.env` en la raíz de la carpeta `api/` y define las siguientes variables:
    ```env
    # Clave secreta utilizada para firmar y asegurar los tokens de autenticación (JWT)
    SECRET_KEY=tu_clave_secreta_super_segura
    
    # Dirección de conexión a la base de datos (Ejemplo para SQLite local)
    DATABASE_URL=sqlite:///./pdam.db
    ```

2.  **Instalación de Dependencias:**
    Ejecuta el siguiente comando para instalar todas las librerías de Python necesarias:
    ```bash
    pip install -r requirements.txt
    ```

### 📱 Frontend (App Móvil)

**Requisitos Previos:** Asegúrate de tener instalado **Flutter**, el **Android SDK** y las **Android SDK Command-line Tools**.

1.  **Instalar Paquetes:**
    Navega al directorio del proyecto móvil y ejecuta el siguiente comando para descargar las dependencias:
    ```bash
    flutter pub get
    ```

---
**Autor:** Nelson - Estudiante de Ingeniería de Sistemas e Informática.
