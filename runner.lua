-- runner.lua (Functional - Direct Collection Access)

-- Configuration Constants
local DB_NAME = "obfuscator_db" -- DB is often encoded in the URI
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- Collection name is used here

-- 1. Setup Prometheus Dependencies
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus.prometheus not found. Check folder name is 'prometheus'.\n")
    os.exit(1)
end
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- 2. Get Environment Variables
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"
local job_id = os.getenv("JOB_ID") or ""
local mongo_uri = os.getenv("MONGO_URI") or ""

if job_id == "" or mongo_uri == "" then
    io.stderr:write("Error: Missing JOB_ID or MONGO_URI environment variables.\n")
    os.exit(1)
end

-- 3. Run Obfuscation
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")

-- 4. MongoDB Database Update
local mongo_ok, mongo = pcall(require, "mongo")
if not mongo_ok then
    io.stderr:write("Error: Lua-Mongo driver not found. Did luarocks install fail?\n")
    os.exit(1)
end

local collection = nil
local db_error = "Unknown failure during client initialization."
local client = nil -- Retain client for optional close call

-- CRITICAL FIX: The constructor returns the collection object directly.
-- The URI is expected to contain the database name, and we add the collection name here.
local collection_success, collection_or_err = pcall(function()
    -- This specific driver version appears to return the collection handler directly.
    return mongo.Client(mongo_uri .. "/" .. COLLECTION_NAME)
end)

if collection_success and (type(collection_or_err) == 'table' or type(collection_or_err) == 'userdata') then
    collection = collection_or_err
    client = collection_or_err -- Since we only have one object, use it for close if needed
else
    -- This will capture a hard network failure or authentication failure.
    db_error = "Network/Auth Failure (Client/Collection): " .. tostring(collection_or_err)
end


-- Check if we successfully got a collection object before trying to use it
if not collection then
    -- No need to call close since we failed to connect/get collection
    io.stderr:write("Fatal: MongoDB Collection Error. Details: " .. db_error .. "\n")
    os.exit(1)
end

-- Perform the update (using pcall for operational resilience)
local success, update_err = pcall(function()
    collection:update_one(
        { _id = job_id }, 
        { ['$set'] = { 
            status = "COMPLETED", 
            obfuscatedCode = out, 
            completedAt = os.time() 
        }}
    )
end)

-- Ensure client connection is closed only if the method exists
-- We use the collection object (client) to try to close the underlying connection.
if client and type(client.close) == "function" then 
    pcall(client.close, client) 
end

if not success then
    io.stderr:write("MongoDB Update Failed: " .. tostring(update_err) .. "\n")
    os.exit(1)
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

