std = "lua51"
globals = {
  "vim",
}
ignore = {
  "212/_.*",
}
files["tests/"] = {
  unused_args = false,
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "pending",
    "assert",
  },
}
