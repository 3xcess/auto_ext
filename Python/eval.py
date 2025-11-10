import enum

class SystemLoad(enum.Enum):
    CPU     = 0
    IO      = 1
    MEM     = 2
    NET     = 3
    PARALLEL= 4
    IDLE    = 5

def evaluate(cpu, io, mem, network, parallel):

    if network:
        return SystemLoad.NET
    else:
        if io:
            return SystemLoad.IO
        elif cpu:
            if parallel:
                return SystemLoad.PARALLEL
            return SystemLoad.CPU
        elif mem:
            return SystemLoad.MEM

    return SystemLoad.IDLE