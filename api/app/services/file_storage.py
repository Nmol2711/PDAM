# app/services/file_storage.py
import os
import shutil
import uuid
from pathlib import Path
from fastapi import UploadFile

class FileStorageService:
    def __init__(self):
        self.base_dir = Path(__file__).resolve().parent.parent.parent
        
        self.upload_dir = self.base_dir / "static" / "pets"
        
        os.makedirs(self.upload_dir, exist_ok=True)

    def save_pet_image(self, file: UploadFile) -> str:
        """
        Guarda la imagen en el disco duro y devuelve la ruta relativa web 
        para almacenar en la Base de Datos.
        """
        if not file or not file.filename:
            return None

        # 1. Generar nombre único con UUID para evitar colisiones
        extension = file.filename.split(".")[-1]
        filename = f"{uuid.uuid4()}.{extension}"
        
        # 2. Ruta física absoluta donde se escribirá el archivo en el servidor
        file_absolute_path = self.upload_dir / filename
        
        # 3. Guardar el archivo físicamente en el disco
        with open(file_absolute_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # Devuelve: /static/pets/uuid.jpg
        return f"/static/pets/{filename}"