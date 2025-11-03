import enum
from system_load_enum import SystemLoad


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