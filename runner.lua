-- runner.lua (robust, defensive mongo update — tries many driver APIs + runCommand fallback)
-- lowercase, concise, diagnostic-friendly

local DB_NAME = "obfuscator_db"
local COLLECTION_NAME = "PrometheusJobs_UXOAOD"

-- setup path / prometheus
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus.prometheus not found. abort.\n")
    os.exit(1)
end
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- env
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"
local job_id = os.getenv("JOB_ID") or ""
local mongo_uri = os.getenv("MONGO_URI") or ""

if job_id == "" or mongo_uri == "" then
    io.stderr:write("missing JOB_ID or MONGO_URI.\n")
    os.exit(1)
end

-- run obfuscation
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")

-- require mongo module
local mongo_ok, mongo = pcall(require, "mongo")
if not mongo_ok then
    io.stderr:write("lua mongo driver not found (require 'mongo' failed).\n")
    os.exit(1)
end

-- utilities: safe method lookup & call (works for tables and userdata with metatable.__index)
local function find_method(obj, name)
    if type(obj) == "table" and obj[name] ~= nil then
        return obj[name]
    end
    local mt = getmetatable(obj)
    if mt then
        local idx = mt.__index or mt
        if type(idx) == "table" and idx[name] ~= nil then
            return idx[name]
        end
    end
    return nil
end

local function try_call(obj, name, ...)
    local fn = find_method(obj, name)
    if type(fn) == "function" then
        local ok, res_or_err = pcall(fn, obj, ...)
        return ok, res_or_err
    end
    return false, ("method '%s' not found"):format(name)
end

-- try multiple candidate method names in order
local function try_methods(obj, names, ...)
    local tried = {}
    for _,name in ipairs(names) do
        local ok, res_or_err = try_call(obj, name, ...)
        table.insert(tried, name)
        if ok then
            return true, res_or_err, tried
        end
    end
    return false, ("no methods worked: %s"):format(table.concat(names, ", ")), tried
end

-- dump metatable method names for diagnostics
local function dump_methods(obj)
    local mt = getmetatable(obj)
    if not mt then return "(no metatable found)" end
    local idx = mt.__index or mt
    if type(idx) ~= "table" then return "(metatable.__index not a table)" end
    local names = {}
    for k,v in pairs(idx) do
        if type(v) == "function" then names[#names+1] = tostring(k) end
    end
    table.sort(names)
    if #names == 0 then return "(no functions in metatable.__index)" end
    return "available methods:\n- " .. table.concat(names, "\n- ")
end

-- connect logic: try to obtain client/db/collection in many common patterns
local client = nil
local db_obj = nil
local collection = nil
local diagnostics = {}

-- 1) try canonical client constructor
local ok_client, client_obj = pcall(mongo.Client, mongo_uri)
if ok_client and (type(client_obj) == "table" or type(client_obj) == "userdata") then
    client = client_obj
    diagnostics[#diagnostics+1] = "client via mongo.Client(uri)"
else
    diagnostics[#diagnostics+1] = "mongo.Client(uri) failed: " .. tostring(client_obj)
end

-- helper: try to get db from client
local function get_db_from_client(c)
    local names = { "getDatabase", "get_database", "get_db", "db", "database", "getDatabaseHandle" }
    for _,n in ipairs(names) do
        local ok, res = try_call(c, n, DB_NAME)
        if ok and (type(res) == "table" or type(res) == "userdata") then
            diagnostics[#diagnostics+1] = ("db via client:%s"):format(n)
            return res
        end
    end
    return nil
end

-- helper: try to get collection from candidate objects
local function get_collection_from(obj, dbname)
    -- try db:getCollection / get_collection / getCollection
    local db_method_names = { "getCollection", "get_collection", "collection", "get_collection_handle" }
    for _,n in ipairs(db_method_names) do
        local ok, res = try_call(obj, n, COLLECTION_NAME)
        if ok and (type(res) == "table" or type(res) == "userdata") then
            diagnostics[#diagnostics+1] = ("collection via %s"):format(n)
            return res
        end
    end
    -- try client:getCollection(db, coll)
    local client_coll_names = { "getCollection", "get_collection", "get_collection_handle" }
    for _,n in ipairs(client_coll_names) do
        local ok, res = try_call(obj, n, dbname, COLLECTION_NAME)
        if ok and (type(res) == "table" or type(res) == "userdata") then
            diagnostics[#diagnostics+1] = ("collection via client.%s(db,coll)"):format(n)
            return res
        end
    end
    return nil
end

-- attempt patterns in order
if client then
    -- 1a: try client -> db -> collection
    db_obj = get_db_from_client(client)
    if db_obj then
        collection = get_collection_from(db_obj, DB_NAME)
    end

    -- 1b: if still nil, try client:getCollection(db, coll) directly
    if not collection then
        local ok, res = try_methods(client, { "getCollection", "get_collection" }, DB_NAME, COLLECTION_NAME)
        if ok and (type(res) == "table" or type(res) == "userdata") then
            collection = res
            diagnostics[#diagnostics+1] = "collection via client:getCollection(db, coll)"
        end
    end
end

-- 2) some drivers return the collection when you pass DB/collection in the URI
if not collection then
    local ok_coll, coll_obj = pcall(mongo.Client, mongo_uri .. "/" .. DB_NAME .. "/" .. COLLECTION_NAME)
    if ok_coll and (type(coll_obj) == "table" or type(coll_obj) == "userdata") then
        collection = coll_obj
        client = coll_obj
        diagnostics[#diagnostics+1] = "collection via mongo.Client(uri/db/coll)"
    else
        diagnostics[#diagnostics+1] = "mongo.Client(uri/db/coll) not successful or not table/userdata"
    end
end

-- 3) try mongo.connect or mongo.Client.connect style
if not collection then
    local ok_conn, conn_or_err = pcall(function()
        if mongo.connect then return mongo.connect(mongo_uri) end
        if mongo.Client and find_method(mongo.Client, "connect") then
            return try_call(mongo.Client, "connect", mongo_uri)
        end
        return nil
    end)
    if ok_conn and (type(conn_or_err) == "table" or type(conn_or_err) == "userdata") then
        client = conn_or_err
        diagnostics[#diagnostics+1] = "connected via mongo.connect or Client.connect"
        collection = get_collection_from(client, DB_NAME) or nil
    else
        diagnostics[#diagnostics+1] = "mongo.connect(Client). not available"
    end
end

-- if still no collection, try module-level helper names
if not collection then
    local try_names = { "get_collection", "getCollection", "collection" }
    for _,n in ipairs(try_names) do
        if find_method(mongo, n) then
            local ok, col = try_call(mongo, n, mongo_uri, DB_NAME, COLLECTION_NAME)
            if ok and (type(col) == "table" or type(col) == "userdata") then
                collection = col
                client = col
                diagnostics[#diagnostics+1] = ("collection via mongo.%s"):format(n)
                break
            end
        end
    end
end

-- final check
if not collection then
    io.stderr:write("fatal: could not locate collection object. diagnostics:\n- " .. table.concat(diagnostics, "\n- ") .. "\n")
    -- if we have a client and it supports close, close it for cleanliness
    if client and type(find_method(client, "close")) == "function" then pcall(find_method(client, "close"), client) end
    os.exit(1)
end

-- prepare update payload
local selector = { _id = job_id }
local update_doc = { ['$set'] = {
    status = "COMPLETED",
    obfuscatedCode = out,
    completedAt = os.time()
}}

-- try update using many patterns, then fallback to runCommand
local update_attempts = {}

-- common collection update names
local coll_update_names = { "update_one", "updateOne", "update", "replace_one", "replaceOne", "find_one_and_update", "findOneAndUpdate" }
for _,name in ipairs(coll_update_names) do
    local ok, res = try_call(collection, name, selector, update_doc)
    update_attempts[#update_attempts+1] = name .. ": " .. (ok and "ok" or ("fail: " .. tostring(res)))
    if ok then
        io.stdout:write("job " .. job_id .. " updated via " .. name .. "\n")
        if client and type(find_method(client, "close")) == "function" then pcall(find_method(client, "close"), client) end
        os.exit(0)
    end
end

-- some drivers expect (selector, update_doc, options)
for _,name in ipairs({ "update", "updateOne", "update_one" }) do
    local ok, res = try_call(collection, name, selector, update_doc, { upsert = false })
    update_attempts[#update_attempts+1] = name .. "(with opts): " .. (ok and "ok" or ("fail: " .. tostring(res)))
    if ok then
        io.stdout:write("job " .. job_id .. " updated via " .. name .. "(with opts)\n")
        if client and type(find_method(client, "close")) == "function" then pcall(find_method(client, "close"), client) end
        os.exit(0)
    end
end

-- fallback: try a client runCommand/update command pattern
local function try_runcommand_update(c)
    local cmd = {
        update = COLLECTION_NAME,
        updates = {
            { q = selector, u = update_doc, upsert = false }
        }
    }
    local names = { "runCommand", "run_command", "command", "execute" }
    for _,n in ipairs(names) do
        local ok, res = try_call(c, n, cmd)
        update_attempts[#update_attempts+1] = n .. ": " .. (ok and "ok" or ("fail: " .. tostring(res)))
        if ok then
            return true, res
        end
    end
    return false, table.concat(update_attempts, "\n")
end

-- attempt runCommand on client object if available
local ok_rc, rc_res = try_runcommand_update(client)
if ok_rc then
    io.stdout:write("job " .. job_id .. " updated via runCommand fallback\n")
    if client and type(find_method(client, "close")) == "function" then pcall(find_method(client, "close"), client) end
    os.exit(0)
end

-- nothing worked: print diagnostics
local meta_dump = dump_methods(collection)
io.stderr:write("mongo update failed. attempts:\n- " .. table.concat(update_attempts, "\n- ") .. "\ncollection metatable: " .. meta_dump .. "\nclient diagnostics:\n- " .. table.concat(diagnostics, "\n- ") .. "\n")
if client and type(find_method(client, "close")) == "function" then pcall(find_method(client, "close"), client) end
os.exit(1)
