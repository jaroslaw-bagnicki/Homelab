-- Derive the readable `level` field from journald's numeric PRIORITY (syslog severity), which is
-- the field VictoriaLogs displays and filters on. PRIORITY itself is preserved, and nothing is
-- added when a record carries no PRIORITY. See ADR 36.
local levels = { "emerg", "alert", "crit", "error", "warn", "notice", "info", "debug" }

function map_level(tag, timestamp, record)
    local priority = tonumber(record["PRIORITY"])
    if priority ~= nil then
        local level = levels[priority + 1]
        if level ~= nil then
            record["level"] = level
        end
    end
    return 1, timestamp, record
end
