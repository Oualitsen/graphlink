import importlib

from tests.cases import build

_mappers = importlib.import_module("generated.mappers")

for _case in build(type("Mappers", (), {
    "UserEntityMapper": importlib.import_module("generated.mappers.user_entity_mapper").UserEntityMapper,
    "UserMapper": importlib.import_module("generated.mappers.user_mapper").UserMapper,
})):
    globals()["Client" + _case.__name__] = _case
del _case
