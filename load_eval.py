def evaluate(cpu, io, mem, network):
    
    if network:
        return "NETWORKED"
    else:
        if io:
            return "IO"
        elif cpu:
            return "CPU"
        else:
            return "MEM"

    return "IDLE"
