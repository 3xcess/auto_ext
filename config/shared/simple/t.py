import time, math

t0 = time.time()
s = sum(math.sqrt(i) for i in range(10_000_000))
print(f"sum={s:.3f}, elapsed={time.time()-t0:.2f}s")
