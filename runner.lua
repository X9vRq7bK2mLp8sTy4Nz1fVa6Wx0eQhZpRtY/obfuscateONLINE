-- runner.lua (Updated with robust MongoDB connection logic)

-- Configuration Constants
local DB_NAME = "obfuscator_db" 
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- Ensure this is correct

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

-- CRITICAL FIX START: Connect and get the connection object
local client, err = mongo.Client(mongo_uri)
if not client then
    io.stderr:write("Error: Could not create MongoDB client. Details: " .. tostring(err) .. "\n")
    os.exit(1)
end

-- FIX: We must explicitly request a connection from the client
local conn, conn_err = client:get_connection()
if not conn then
    io.stderr:write("Error: Could not establish MongoDB connection. Details: " .. tostring(conn_err) .. "\n")
    client:close()
    os.exit(1)
end

-- Get the collection using the connection object
local collection = conn:get_collection(DB_NAME, COLLECTION_NAME)
-- CRITICAL FIX END

local success, update_err = pcall(function()
    collection:update_one(
        -- IMPORTANT: Using _id field for lookup based on Vercel trigger.js logic
        { _id = job_id }, 
        { ['$set'] = { 
            status = "COMPLETED", 
            obfuscatedCode = out, 
            completedAt = os.time() 
        }}
    )
end)

-- Ensure client connection is closed
client:close()

if not success then
    io.stderr:write("MongoDB Update Failed: " .. tostring(update_err) .. "\n")
    os.exit(1)
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

