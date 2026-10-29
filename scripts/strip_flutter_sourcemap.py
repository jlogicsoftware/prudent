#!/usr/bin/env python3
"""Remove Flutter's reference to its unshipped loader source map."""
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
source = re.sub(r'(?m)^[ \t]*//[#@][ \t]*sourceMappingURL=flutter\.js\.map[ \t]*\r?\n?', '', source)
path.write_text(source)
