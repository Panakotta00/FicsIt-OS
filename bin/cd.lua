local process = require("process")

local p = process.running()

p.environment["PWD"] = filesystem.path(1, p.environment["PWD"], ...)
