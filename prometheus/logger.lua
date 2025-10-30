-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- logger.lua

local logger = {}
local config = require("config");
local colors = require("colors");

logger.LogLevel = {
	Error = 0,
	Warn = 1,
	Log = 2,
	Info = 2,
	Debug = 3,
}

logger.logLevel = logger.LogLevel.Log;

logger.debugCallback = function(...)
	local args = {...};
	local message = table.concat(args, " ");
	print(colors(config.NameUpper .. ": " .. message, "grey"));
end;

function logger:debug(...)
	if self.logLevel >= self.LogLevel.Debug then
		self.debugCallback(...);
	end
end

logger.logCallback = function(...)
	local args = {...};
	local message = table.concat(args, " ");
	print(colors(config.NameUpper .. ": ", "magenta") .. message);
end;

function logger:log(...)
	if self.logLevel >= self.LogLevel.Log then
		self.logCallback(...);
	end
end

function logger:info(...)
	if self.logLevel >= self.LogLevel.Log then
		self.logCallback(...);
	end
end

logger.warnCallback = function(...)
	local args = {...};
	local message = table.concat(args, " ");
	print(colors(config.NameUpper .. ": " .. message, "yellow"));
end;

function logger:warn(...)
	if self.logLevel >= self.LogLevel.Warn then
		self.warnCallback(...);
	end
end

logger.errorCallback = function(...)
	local args = {...};
	local message = table.concat(args, " ");
	print(colors(config.NameUpper .. ": " .. message, "red"))
	error(message);
end;

function logger:error(...)
	self.errorCallback(...);
	error(config.NameUpper .. ": logger.errorCallback did not throw an Error!");
end


return logger;
