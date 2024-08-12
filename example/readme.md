# Example for treqmon

## Requirements

- twebserver 1.47.49 or later
- thtml
- tjson

## Compile Templates

```bash
cd treqmon
tclsh9.0 $THTML_DIR/bin/thtml-compiledir.tcl \
  tcl \
  $(pwd)/example/ \
  $(pwd)/example/www/
```