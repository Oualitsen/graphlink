import os
from typing import List, Sequence, Union

COMMA = os.environ.get("REST_VARIANT") == "comma"
BRACKET = COMMA
PORT = 9986 if COMMA else 9985


def key(base: str, path: Sequence[Union[str, int]] = ()) -> str:
    out = base
    for part in path:
        out = f"{out}[{part}]" if BRACKET else f"{out}.{part}"
    return out


def lst(name: str, values: List[str]) -> List[str]:
    if COMMA:
        return [f"{name}={','.join(values)}"]
    return [f"{name}={v}" for v in values]
