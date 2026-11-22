from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class AddressEntity:
    street: str


@dataclass
class UserEntity:
    id: str
    full_name: str
    addresses: List[AddressEntity] = field(default_factory=list)
    nick: Optional[str] = None
    home: Optional[AddressEntity] = None
