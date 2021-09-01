local gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1]
local screen = computer.getPCIDevices(findClass("FINComputerScreen"))[1]

gpu:bindScreen(screen)
event.listen(gpu)
