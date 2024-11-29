# Stop currently running process before launching program
```lua
{
  name = "PYTHON: Run",
  builder = function(cache)
    vim.cmd("wall")
    return {
      cmd = {
        "\x03",
        "python tcp_server.py",
      },
    }
    -- See the links below to find out more info about Control Characters
    -- https://en.wikipedia.org/wiki/Control_character
    -- https://donsnotes.com/tech/charsets/ascii.html
    -- Also you may want to use "\x0C" control character which clear the screen before launching the task
  end,
```
