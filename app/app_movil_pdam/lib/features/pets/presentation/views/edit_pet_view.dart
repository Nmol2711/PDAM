import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class EditPetView extends StatefulWidget {
  final Pet pet;

  const EditPetView({super.key, required this.pet});

  @override
  State<EditPetView> createState() => _EditPetViewState();
}

class _EditPetViewState extends State<EditPetView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _weightController;

  late TypePest _selectedSpecies;
  late DateTime _selectedBirthDate;
  late bool _reproductiveStatus;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  String _getDefaultAssetPath(TypePest species) {
    switch (species) {
      case TypePest.canino:
        return "assets/imgs/perro.png";
      case TypePest.felino:
      case TypePest.otros:
        return "assets/imgs/gato_1.png";
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.pet.name);
    _weightController = TextEditingController(text: widget.pet.weight.toString());
    _selectedSpecies = widget.pet.species;
    _selectedBirthDate = widget.pet.birthDate;
    _reproductiveStatus = widget.pet.reproductiveStatus;
  }

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
      initialDate: _selectedBirthDate,
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
      context.read<PetBloc>().add(
            PetUpdatePressed(
              petId: widget.pet.id,
              name: _nameController.text.trim(),
              species: _selectedSpecies,
              birthDate: _selectedBirthDate,
              weight: double.parse(_weightController.text),
              reproductiveStatus: _reproductiveStatus,
              imageFile: _selectedImage,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar ${widget.pet.name}'),
        elevation: 0,
      ),
      body: BlocListener<PetBloc, PetState>(
        listener: (context, state) {
          if (state is PetActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
            context.read<PetBloc>().add(PetsLoadedRequested());
            Navigator.pop(context); // Sale de EditPetView
            Navigator.pop(context); // Sale de PetDetailView y vuelve a PetsView
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
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- AVATAR / FOTO DE LA MASCOTA ---
                Center(
                  child: GestureDetector(
                    onTap: () => _showImageSourceActionSheet(context),
                    child: Stack(
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _selectedImage != null
                              ? Image.file(_selectedImage!, fit: BoxFit.cover)
                              : (widget.pet.imgUrl != null && widget.pet.imgUrl!.isNotEmpty
                                  ? Image.network(
                                      widget.pet.imgUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Image.asset(
                                          _getDefaultAssetPath(widget.pet.species),
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    )
                                  : Image.asset(
                                      _getDefaultAssetPath(widget.pet.species),
                                      fit: BoxFit.cover,
                                    )),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            radius: 18,
                            child: const Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // --- NOMBRE ---
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la mascota',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- ESPECIE ---
                DropdownButtonFormField<TypePest>(
                  value: _selectedSpecies,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Especie',
                    prefixIcon: Icon(Icons.pets_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
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
                    if (newValue != null) {
                      setState(() {
                        _selectedSpecies = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // --- FECHA DE NACIMIENTO ---
                InkWell(
                  onTap: () => _selectBirthDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      prefixIcon: Icon(Icons.cake_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    child: Text(
                      '${_selectedBirthDate.toLocal()}'.split(' ')[0],
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- PESO ---
                TextFormField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Peso (kg)',
                    prefixIcon: Icon(Icons.monitor_weight_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
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
                const SizedBox(height: 16),

                // --- ESTADO REPRODUCTIVO ---
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text('¿Está esterilizado / castrado?'),
                    subtitle: const Text('Ajusta el cálculo calórico automáticamente'),
                    value: _reproductiveStatus,
                    onChanged: (bool value) {
                      setState(() {
                        _reproductiveStatus = value;
                      });
                    },
                    secondary: const Icon(Icons.medical_services_outlined),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // --- BOTÓN DE ACTUALIZAR ---
                BlocBuilder<PetBloc, PetState>(
                  builder: (context, state) {
                    final isLoading = state is PetLoading;

                    return FilledButton(
                      onPressed: isLoading ? null : _submitForm,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Actualizar Mascota',
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
