# Bartholomew (the configuration language)

A basic configuration language

---

## Syntax

(example)
```bartholomew
# basic top-level fields
name = "me server";

# it has categories
server {
    # numbers
    port = 4389;
    
    #booleans
    multi_threaded = false;

    # you can nest categories
    log {
        enable = true;
        supress_requests = true;

        # strings don't need to be quoted
        #   (if it doesn't include whitespace)
        file = server.log;

        # it has lists too
        #   (commas are for elderly languages, whitespace is enough)
        events = [
            error
            info
        ]
    }
}
```
