import enum

class SystemLoad(enum.Enum):
    CPU     = 0
    IO      = 1
    MEM     = 2
    NET     = 3
    IDLE    = 5

def evaluate(cpu, io, mem, network):

    if network:
        return SystemLoad.NET
    else:
        if io:
            return SystemLoad.IO
        elif cpu:
            return SystemLoad.CPU
        elif mem:
            return SystemLoad.MEM

    return SystemLoad.IDLE