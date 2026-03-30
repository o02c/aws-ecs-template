local cjson = require("cjson.safe")

function parse_json(tag, timestamp, record)
    local log = record["log"]
    if log then
        local parsed = cjson.decode(log)
        if parsed then
            for k, v in pairs(parsed) do
                record[k] = v
            end
            record["log"] = nil
        end
    end
    return 1, timestamp, record
end
