import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart'; // Donde está TypePest
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class CreatePetView extends StatefulWidget {
  const CreatePetView({super.key});

  @override
  State<CreatePetView> createState() => _CreatePetViewState();
}

class _CreatePetViewState extends State<CreatePetView> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();

  // Variables de estado local del formulario
  TypePest? _selectedSpecies;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// Método para seleccionar la imagen usando ImagePicker
  Future<void> _pickImage(ImageSource source) async {
    try {
      // pickImage garantiza nativamente que solo filtre formatos de imagen (PNG, JPEG, etc) y no PDFs
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80, // Comprime un poco para optimizar la subida a FastAPI
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar la imagen: $e')),
      );
    }
  }

  /// Muestra la hoja inferior para elegir entre Cámara o Galería
  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Envía el evento al BLoC si el formulario es válido
  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      if (_selectedSpecies == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecciona una especie')),
        );
        return;
      }

      // Disparamos el evento hacia tu PetBloc
      context.read<PetBloc>().add(
        PetCreatePressed(
          name: _nameController.text.trim(),
          species: _selectedSpecies!,
          age: int.parse(_ageController.text),
          weight: double.parse(_weightController.text),
          imageFile: _selectedImage,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Mascota')),
      // El BlocListener escucha los cambios de estado para navegación/mensajes
      body: BlocListener<PetBloc, PetState>(
        listener: (context, state) {
          if (state is PetDetailLoaded || state is PetActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('¡Mascota registrada con éxito!')),
            );
            // Refrescamos la lista de mascotas global antes de volver
            context.read<PetBloc>().add(PetsLoadedRequested());
            Navigator.pop(context); // Regresa al dashboard/Home
          } else if (state is PetError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── SECCIÓN DE SELECCIÓN DE IMAGEN ───
                Center(
                  child: GestureDetector(
                    onTap: () => _showImageSourceActionSheet(context),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : null,
                          child: _selectedImage == null
                              ? Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: Colors.grey[600],
                                )
                              : null,
                        ),
                        if (_selectedImage != null)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              backgroundColor: Colors.blue,
                              radius: 18,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                onPressed: () =>
                                    _showImageSourceActionSheet(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ─── CAMPO: NOMBRE ───
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la mascota',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ─── CAMPO: ESPECIE (ENUM) ───
                DropdownButtonFormField<TypePest>(
                  initialValue: _selectedSpecies,
                  decoration: const InputDecoration(
                    labelText: 'Especie',
                    prefixIcon: Icon(Icons.pets),
                    border: OutlineInputBorder(),
                  ),
                  items: TypePest.values.map((TypePest type) {
                    return DropdownMenuItem<TypePest>(
                      value: type,
                      // Transforma el valor del enum a un String legible (ej: Canino, Felino)
                      child: Text(type.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (TypePest? newValue) {
                    setState(() {
                      _selectedSpecies = newValue;
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Selecciona una especie' : null,
                ),
                const SizedBox(height: 16),

                // ─── CAMPO: EDAD ───
                TextFormField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Edad (Años o meses)',
                    prefixIcon: Icon(Icons.cake_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'La edad es obligatoria';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Introduce un número entero válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ─── CAMPO: PESO ───
                TextFormField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Peso (kg)',
                    prefixIcon: Icon(Icons.monitor_weight_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El peso es obligatorio';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Introduce un peso decimal válido (ej: 4.5)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // ─── BOTÓN DE GUARDAR CON ESTADO LOADING ───
                BlocBuilder<PetBloc, PetState>(
                  builder: (context, state) {
                    final isLoading = state is PetLoading;

                    return ElevatedButton(
                      onPressed: isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Guardar Mascota',
                              style: TextStyle(fontSize: 16),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
