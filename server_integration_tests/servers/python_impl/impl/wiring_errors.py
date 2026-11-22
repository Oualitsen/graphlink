from generated.errors.err_conflict import ErrConflict
from generated.errors.err_forbidden import ErrForbidden
from generated.errors.err_not_found import ErrNotFound
from generated.types.err_item import ErrItem


class ErrItemServiceImpl:
    async def err_probe(self, id, context):
        if id == "missing":
            raise ErrNotFound(id=id, message=f"Item {id} not found")
        if id == "forbidden":
            raise ErrForbidden(message="No access")
        if id == "boom":
            raise RuntimeError("secret detail")
        return ErrItem(id=id)

    async def err_rest(self, id, context):
        if id == "missing":
            raise ErrNotFound(id=id, message=f"Item {id} not found")
        if id == "conflict":
            raise ErrConflict(reason="duplicate", message="Conflict")
        if id == "boom":
            raise RuntimeError("secret detail")
        return ErrItem(id=id)
