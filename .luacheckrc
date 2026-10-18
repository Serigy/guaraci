std = "lua54"
max_line_length = 140
-- Unused arguments are intentional in handler/middleware/method signatures.
ignore = { "212" }
exclude_files = { "openwiki/**", "docs/**", "history/**" }
files["tests"] = { std = "+busted" }
