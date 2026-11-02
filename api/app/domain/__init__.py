"""Dominio puro de las specs 014 y 022: catálogos, tiempo, stock, consulta y panel.

Sin SQLAlchemy, sin FastAPI y con el instante, el stock y la zona como
parámetros, para que las reglas se prueben sin base de datos y los servicios
solo orquesten. La spec 022 añade `panel`: las cifras del resumen con la
actividad registrada y las ocurrencias dispensables.
"""
