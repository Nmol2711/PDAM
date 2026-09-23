# Reglas de Arquitectura: Capa de Presentación (Flutter)

Este documento define las directrices obligatorias para la implementación y estructuración de la capa de presentación en la aplicación.

---

## 1. Estructura de Carpetas

Dentro de cada módulo en la capa de presentación (`presentation/`), la estructura debe dividirse estrictamente en tres directorios:

presentation/
└── [nombre_modulo]/
├── bloc/ # Eventos, Estados y BLoC / Cubit
├── view/ # Pantalla principal (Scaffold, AppBar, layout macro)
└── widgets/ # Sub-widgets extraídos de la pantalla



---

## 2. Gestión de Estado (BLoC vs. setState)

### Regla Principal: BLoC Integrado
Toda la lógica de negocio, manejo de estados de la UI, llamadas a casos de uso/repositorios y flujos de información deben gestionarse exclusivamente utilizando la librería `flutter_bloc` (`BlocBuilder`, `BlocListener`, `BlocConsumer`, `BlocProvider`).

### Restricción Severa del Uso de `setState`:
- **Prohibición**: Está estrictamente prohibido utilizar `setState` para gestionar datos de negocio, respuestas de API, o cualquier estado compartido entre múltiples componentes de la pantalla.
- **Excepción Permitida**: El uso de `setState` se permite única y exclusivamente dentro de un `StatefulWidget` para cambios de UI efímeros y puramente locales que no afecten a otros componentes (por ejemplo: controlar el foco o visibilidad local de un campo de texto, o animaciones estéticas locales). Si el estado debe influir en otro widget, debe promoverse obligatoriamente a un BLoC.

---

## 3. Limpieza y Modularización de las Views (`/view`)

- **Responsabilidad Única**: Las clases dentro del directorio `/view` deben ser lo más declarativas y limpias posible. Solo deben definir la estructura macro de la pantalla (ej. `Scaffold`, `AppBar`, `SafeArea`, y contenedores estructurales como `Column`, `Row` o `Flex`).
- **Regla de Extracción Obligatoria**: Ninguna vista en `/view` debe contener lógica visual compleja ni bloques de código extensos. Si un sub-componente (un formulario, tarjeta, panel de botones, elemento de lista, etc.) supera las 30-40 líneas de código, debe ser extraído a un archivo independiente dentro del directorio `/widgets/`.
- **Prohibición de Métodos `_buildWidget()`**: Está prohibido dividir las interfaces usando métodos privados que retornen widgets (ej. `Widget _buildHeader()`). Todo componente debe ser un `StatelessWidget` o `StatefulWidget` propio dentro de la carpeta `/widgets/` para maximizar la optimización del árbol de widgets.

---

## 4. Optimización de Rendimiento y Evitación de Reconstrucciones Masivas

Para prevenir relanzamientos innecesarios de la pantalla (screen rebuilds) y garantizar un alto rendimiento:

- **Localización Directa de `BlocBuilder`**:
  - Evita envolver toda la pantalla (`Scaffold` o la view principal) dentro de un único `BlocBuilder`.
  - El `BlocBuilder` debe colocarse en el nivel más bajo posible del árbol de componentes, específicamente dentro de los sub-widgets de la carpeta `/widgets/` que realmente consuman ese estado.

- **Uso de `buildWhen` y `listenWhen`**:
  - Utiliza la propiedad `buildWhen` en los `BlocBuilder` para filtrar actualizaciones y evitar que un sub-widget se vuelva a dibujar si las propiedades del estado que utiliza no han cambiado.

- **Uso Exhaustivo de `const`**:
  - Utiliza constructores `const` en todos los widgets, constantes de diseño (`TextStyle`, `EdgeInsets`), decoraciones e iconos estáticos para evitar que Flutter cree instancias redundantes en memoria.

---

## 5. Ejemplo de Implementación Referencial

### ❌ Estructura Incorrecta (View sobrecargada, reconstrucción global y métodos privados)

```dart
// view/profile_view.dart
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: BlocBuilder<ProfileBloc, ProfileState>( // ❌ Reconstruye toda la pantalla ante cualquier cambio
        builder: (context, state) {
          return Column(
            children: [
              _buildHeader(state), // ❌ Uso de método privado en vez de widget extraído
              Text(state.userName),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(ProfileState state) { // ❌ Mala práctica en Flutter
    return Container(child: Text(state.userEmail));
  }
}
```


## ✅ Estructura Correcta (Modular, limpia, con BLoC localizado y widgets extraídos)

```dart
// view/profile_view.dart
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: CustomProfileAppBar(),
      body: Column(
        children: [
          ProfileHeaderWidget(), // Extraído en /widgets/profile_header_widget.dart
          ProfileDetailsWidget(), // Extraído en /widgets/profile_details_widget.dart
        ],
      ),
    );
  }
}

// widgets/profile_header_widget.dart
class ProfileHeaderWidget extends StatelessWidget {
  const ProfileHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      buildWhen: (previous, current) => previous.avatarUrl != current.avatarUrl, // ⚡ Optimizado
      builder: (context, state) {
        return CircleAvatar(
          backgroundImage: NetworkImage(state.avatarUrl),
        );
      },
    );
  }
}
```
Nota: Estas reglas son obligatorias y deben aplicarse en todos los módulos de la capa de presentación para garantizar mantenibilidad, escalabilidad y rendimiento óptimo en la aplicación.
