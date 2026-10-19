-- Log File Info: the loaded file name, the sheets and a timestamp. A good
-- starting point for an autorun program.
print("File: " .. (FileName ~= "" and FileName or "(not saved yet)"))
print(`Sheets: {#Sheets} · active: {ActiveSheet.Name}`)
print("Run at: " .. (os and os.date and os.date("%Y-%m-%d %H:%M:%S") or "unknown"))
