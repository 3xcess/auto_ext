from enum import Enum

class SystemLoad(Enum):
    CPU = 0
    IO = 1
    MEM = 2
    NET = 3
    PARALLEL = 4
    IDLE = 5