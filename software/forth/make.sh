#!/bin/bash
docker run --rm -v "$(pwd)":/src -w /src bkuker/tms9900-gcc:local make "$@"
