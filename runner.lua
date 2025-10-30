-- runner.lua (Finalized MongoDB API usage for GitHub Actions)

-- Configuration Constants
local DB_NAME = "obfuscator_db" 
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- Ensure this matches your Vercel API

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

local client = nil
local collection = nil
local db_error = "Connection initialization failed."

-- CRITICAL FIX START: Connect and retrieve collection in the most robust manner
local client_success, client_or_err = pcall(mongo.Client, mongo_uri)

if client_success and type(client_or_err) == 'table' then
    client = client_or_err
    
    -- DEFENSE: Attempt to get the collection directly, bypassing get_connection()
    local collection_success, collection_or_err = pcall(function()
        return client:get_collection(DB_NAME, COLLECTION_NAME)
    end)

    if collection_success and type(collection_or_err) == 'table' then
        collection = collection_or_err
    else
        -- FIX: Capture the actual connection error here
        db_error = "Failed to retrieve collection (likely connection issue): " .. tostring(collection_or_err)
    end
else
    -- FIX: Capture the actual client creation error here
    db_error = "Could not create MongoDB client object: " .. tostring(client_or_err)
end

-- Check if we successfully got a collection object before trying to use it
if not collection then
    -- Clean up client defensively if it was created
    if client and type(client.close) == "function" then pcall(client.close, client) end
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
if client and type(client.close) == "function" then 
    pcall(client.close, client) 
end
-- CRITICAL FIX END

if not success then
    io.stderr:write("MongoDB Update Failed: " .. tostring(update_err) .. "\n")
    os.exit(1)
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

