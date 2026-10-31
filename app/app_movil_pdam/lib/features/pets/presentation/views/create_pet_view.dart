import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class CreatePetView extends StatefulWidget {
  const CreatePetView({super.key});

  @override
  State<CreatePetView> createState() => _CreatePetViewState();
}

class _CreatePetViewState extends State<CreatePetView> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _weightController = TextEditingController();

  TypePest? _selectedSpecies;
  DateTime? _selectedBirthDate;
  bool _reproductiveStatus = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
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

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetRadius),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
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

  Future<void> _selectBirthDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedBirthDate = picked;
      });
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      if (_selectedSpecies == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecciona una especie')),
        );
        return;
      }
      if (_selectedBirthDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, selecciona la fecha de nacimiento'),
          ),
        );
        return;
      }

      context.read<PetBloc>().add(
        PetCreatePressed(
          name: _nameController.text.trim(),
          species: _selectedSpecies!,
          birthDate: _selectedBirthDate!,
          weight: double.parse(_weightController.text),
          reproductiveStatus: _reproductiveStatus,
          imageFile: _selectedImage,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Mascota')),
      body: BlocListener<PetBloc, PetState>(
        listener: (context, state) {
          if (state is PetDetailLoaded || state is PetActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: semantica.success,
                content: Text(
                  '¡Mascota registrada con éxito!',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: semantica.onSuccess),
                ),
              ),
            );
            context.read<PetBloc>().add(PetsLoadedRequested());
            Navigator.pop(context);
          } else if (state is PetError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: esquema.error,
                content: Text(
                  state.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: esquema.onError),
                ),
              ),
            );
          }
        },
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageFor(ancho),
            vertical: AppSpacing.page,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── AVATAR / FOTO DE LA MASCOTA ───
                Center(
                  child: GestureDetector(
                    onTap: () => _showImageSourceActionSheet(context),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: esquema.primaryContainer.withValues(
                            alpha: 0.4,
                          ),
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : null,
                          child: _selectedImage == null
                              ? Icon(
                                  Icons.camera_alt_outlined,
                                  size: 36,
                                  color: esquema.primary,
                                )
                              : null,
                        ),
                        if (_selectedImage != null)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              backgroundColor: esquema.primary,
                              radius: 18,
                              child: Icon(
                                Icons.edit,
                                size: 16,
                                color: esquema.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),

                // ─── NOMBRE ───
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la mascota',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.fieldGap),

                // ─── ESPECIE ───
                DropdownButtonFormField<TypePest>(
                  value: _selectedSpecies,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Especie',
                    prefixIcon: Icon(Icons.pets_outlined),
                  ),
                  items: TypePest.values.map((TypePest type) {
                    return DropdownMenuItem<TypePest>(
                      value: type,
                      child: Text(
                        type.name.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                const SizedBox(height: AppSpacing.fieldGap),

                // ─── FECHA DE NACIMIENTO ───
                InkWell(
                  onTap: () => _selectBirthDate(context),
                  borderRadius: AppRadii.controlRadius,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _selectedBirthDate == null
                          ? 'Seleccionar fecha'
                          : '${_selectedBirthDate!.toLocal()}'.split(' ')[0],
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedBirthDate == null
                            ? esquema.onSurfaceVariant
                            : esquema.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.fieldGap),

                // ─── PESO ───
                TextFormField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Peso (kg)',
                    prefixIcon: Icon(Icons.monitor_weight_outlined),
                    suffixText: 'kg',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El peso es obligatorio';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Introduce un peso válido (ej: 4.5)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.fieldGap),

                // ─── ESTADO REPRODUCTIVO ───
                Card(
                  child: SwitchListTile(
                    title: const Text('¿Está esterilizado / castrado?'),
                    subtitle: const Text(
                      'Ajusta el cálculo calórico automáticamente',
                    ),
                    value: _reproductiveStatus,
                    onChanged: (bool value) {
                      setState(() {
                        _reproductiveStatus = value;
                      });
                    },
                    secondary: const Icon(Icons.medical_services_outlined),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.cardRadius,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),

                // ─── BOTÓN DE GUARDAR ───
                BlocBuilder<PetBloc, PetState>(
                  builder: (context, state) {
                    final isLoading = state is PetLoading;

                    return AppCtaButton(
                      onPressed: isLoading ? null : _submitForm,
                      child: isLoading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: esquema.onSurfaceVariant,
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
