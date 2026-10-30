"""Esquemas HTTP de la cuenta de usuario (spec 015).

Solo describen la forma de la petición y de la respuesta. No validan el correo
ni la contraseña: esa validación vive en `app.domain.cuenta` y en
`app.services.account_service`, de modo que ningún rechazo de negocio cae en la
validación automática del framework y responde 422 (RF-11, §5.4).
"""

from typing import Any, Optional

from pydantic import BaseModel, ConfigDict


class AccountProfile(BaseModel):
    """Perfil de la cuenta: identidad interna, correo y estado informativo.

    `id` se conserva por compatibilidad con el contrato anterior y la app no lo
    muestra. El correo viaja siempre normalizado (RF-06).
    """

    id: int
    email: str
    is_active: bool

    class Config:
        from_attributes = True


class AccountUpdateRequest(BaseModel):
    """Actualización del perfil: ambos campos son opcionales.

    La confirmación de la contraseña no viaja al servidor (la valida la app). No
    se aplican restricciones de Pydantic: un correo vacío, inválido o una
    contraseña débil se rechazan en el servicio con el código del catálogo, no
    con un 422.
    """

    email: Optional[str] = None
    new_password: Optional[str] = None


class AccountUpdateResponse(BaseModel):
    """Resultado de la actualización.

    `access_token` y `token_type` son `null` cuando el correo no cambia, porque
    el token vigente se conserva (RF-10).
    """

    email: str
    is_active: bool
    access_token: Optional[str] = None
    token_type: Optional[str] = None


class AccountDeleteRequest(BaseModel):
    """Confirmación destructiva de la baja: la contraseña actual (RF-17).

    `password` se declara `Any` a propósito: un cuerpo ausente, `null` o con un
    tipo inesperado debe llegar al servicio y responder 400 `invalid_password`,
    nunca un 422 de validación del framework. La contraseña se usa solo para la
    verificación y no se persiste ni se registra (RNF-06).
    """

    model_config = ConfigDict(extra="ignore")

    password: Any = None


class AccountDeleteResponse(BaseModel):
    """Resultado de la baja. `deleted` es `true` también si la cuenta ya no existía."""

    deleted: bool
