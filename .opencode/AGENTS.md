**AGENTS.md**  
**Repository Overview**  
- **Backend (** **api/** **)**: FastAPI (Python) application handling business logic, persistence, and hardware communication. Entrypoint: api/app/main.py.  
- **Frontend (** **app/app_movil_pdam/** **)**: Flutter & Dart mobile application using Clean Architecture and BLoC state management. Entrypoint: app/app_movil_pdam/lib/main.dart.  
- **Hardware (** **arduino/** **)**: Arduino sketches for physical dispenser activation and sensors.  
**Developer Commands**  
**Backend (**api/ **)**  
- **Environment Setup**: Copy api/.env-example to api/.env and configure SECRET_KEY and DATABASE_URL.  
- **Install Dependencies**: pip install -r requirements.txt (run inside api/).  
- **Run Development Server**: uvicorn app.main:app --reload (run from api/).  
- **Run Tests**: python3 -m pytest (run from api/).  
**Frontend (**app/app_movil_pdam/ **)**  
- **Install Dependencies**: flutter pub get (run inside app/app_movil_pdam/).  
- **Run Application**: flutter run (run inside app/app_movil_pdam/).  
- **Run Tests**: flutter test (run inside app/app_movil_pdam/).  
**Guía de Dominio Nutricional Canine & Feline (WSAVA 2011)**  
**1. Atributos Requeridos en la Entidad Mascota (pets)**  
- species: 'dog' | 'cat'  
- weight: float (en kg)  
- bcs: int (escala 1 a 9)  
- mcs: 'normal' | 'mild' | 'moderate' | 'marked'  
- reproductive_status: 'intact' | 'neutered'  
- life_stage: 'growth' | 'adult' | 'geriatric' | 'gestation' | 'lactation'  
- activity_level: 'low' | 'medium' | 'high'  
**2. Cálculo de Requerimiento Basal (RER)**  
- Formula RER: RER = 70 * (weight ^ 0.75) (Aplica para perros y gatos)  
**3. Factores Multiplicadores para MER (Maintenance Energy Requirement)**  
El MER se calcula multiplicando RER * Factor:  
**Perros (Dogs):**  
- Adulto entero: 1.8  
- Adulto castrado: 1.6  
- Bajo nivel de actividad / Propenso a obesidad: 1.2 - 1.4  
- Crecimiento (<4 meses): 3.0  
- Crecimiento (>4 meses): 2.0  
**Gatos (Cats):**  
- Adulto entero: 1.4  
- Adulto castrado: 1.2  
- Inactivo / Propenso a obesidad: 1.0  
- Crecimiento: 2.5  
**4. Validaciones Clave del Negocio**  
- **Alerta de Variabilidad:** Incluir advertencia indicando que MER varía ±30% en perros y ±50% en gatos.  
- **Riesgo Metabólico:** Si mcs != 'normal', disparar alerta "Riesgo de Desequilibrio Metabólico" independientemente del BCS.  
- **Límite de Snacks:**Snack_Kcal <= MER * 0.10. Recalcular comida principal: Main_Ration_Kcal = MER - Snack_Kcal.  
   
   
Importanta:  Seguir las reglas en Rules.md  
   
