import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';

import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PetItem extends StatelessWidget {
  final Pet pet;
  const PetItem({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: InkWell(
        onTap: () {
          context.push('/detail_pet', extra: pet);
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // ─── SECCIÓN DE LA IMAGEN ───
              _buildPetImage(),

              const SizedBox(width: 16), // Espaciado entre imagen e información
              // ─── SECCIÓN DE LA INFORMACIÓN ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${pet.name} • ${pet.age} años",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Peso: ${pet.weight} kg",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Método especializado para gestionar el renderizado de la imagen
  Widget _buildPetImage() {
    const double imageSize = 75;

    // 1. Si el backend mandó la imagen, intentamos cargarla por red
    if (pet.imgUrl != null && pet.imgUrl!.isNotEmpty) {
      // Concatenamos tu IP base con el path relativo del backend

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          pet.imgUrl!,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.cover,
          // Muestra un indicador mientras se descarga la imagen
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const SizedBox(
              width: imageSize,
              height: imageSize,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          // 💡 AQUÍ CAPTURAMOS SI LA URL FALLA O DA ERROR
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAssetImage(imageSize);
          },
        ),
      );
    }

    // 2. Si no viene imagen desde el backend, cargamos directamente el asset por defecto
    return _buildDefaultAssetImage(imageSize);
  }

  /// Método para pintar el asset local correspondiente si la red falla o está vacío
  Widget _buildDefaultAssetImage(double size) {
    String assetPath;

    switch (pet.species) {
      case TypePest.canino:
        assetPath = "assets/imgs/perro.png";
        break;
      case TypePest.felino:
        assetPath = "assets/imgs/gato_1.png";
        break;
      case TypePest.otros:
        assetPath =
            "assets/imgs/gato_1.png"; // temporal mientras agregas los demás
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
