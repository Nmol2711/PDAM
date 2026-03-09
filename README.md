# PDAM - Prototipo de Dispensador Automático de Alimento para Mascotas

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