-- runner.lua (Final Diagnostic Check for MongoDB API)

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
local db_error = "Unknown failure during client initialization."

-- Function to print all methods/keys available on an object
local function dump_methods(obj)
    local t = {}
    for k,v in pairs(getmetatable(obj) or obj) do
        if type(v) == 'function' then
            t[#t+1] = tostring(k)
        end
    end
    table.sort(t)
    return "\nAvailable Client Methods:\n- " .. table.concat(t, "\n- ")
end

-- CRITICAL FIX START: Connect and retrieve collection using defensive API checks
local client_success, client_or_err = pcall(mongo.Client, mongo_uri)

if client_success and type(client_or_err) == 'table' then
    client = client_or_err
    
    local collection_success, collection_or_err = pcall(function()
        -- Attempt 1: getDatabase -> getCollection (most common pattern)
        if type(client.getDatabase) == "function" then
            local db = client:getDatabase(DB_NAME)
            return db:getCollection(COLLECTION_NAME)
        end
        
        -- Attempt 2: get_database -> get_collection (snake_case pattern)
        if type(client.get_database) == "function" then
            local db = client:get_database(DB_NAME)
            return db:get_collection(COLLECTION_NAME)
        end

        -- Attempt 3: direct get_collection (the failing pattern, but included for completeness)
        if type(client.get_collection) == "function" then
            return client:get_collection(DB_NAME, COLLECTION_NAME)
        end

        -- If none of the above methods exist, force a readable error
        error("No suitable method found to retrieve collection.")
    end)

    if collection_success and type(collection_or_err) == 'table' then
        collection = collection_or_err
    else
        -- If collection retrieval failed, capture the error and dump the methods
        db_error = "API Method or Network Failure: " .. tostring(collection_or_err) .. dump_methods(client)
    end
else
    -- Client creation failed (this is rare if the URI is formatted correctly)
    db_error = "Client Object Creation Failed: " .. tostring(client_or_err)
end

-- Check if we successfully got a collection object before trying to use it
if not collection then
    -- Clean up client defensively if it was created
    if client and type(client.close) == "function" then pcall(client.close, client) end
    -- Print the collected, specific error (which now includes method names!)
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

