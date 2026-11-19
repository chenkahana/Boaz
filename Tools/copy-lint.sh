#!/bin/sh
# Fails on hand-built plurals and percentages (docs/copy.md). Run from the repository root.
status=0
if grep -rnE '\? "" : "s"' Apps; then
    echo "error: build plurals with ^[\(count) noun](inflect: true), not count == 1 ? \"\" : \"s\" (docs/copy.md)"
    status=1
fi
if grep -rnE '\* 100\)[^"]*\)%' Apps; then
    echo "error: format percentages with .percent, not \"\\(Int(value * 100))%\" (docs/copy.md)"
    status=1
fi
exit $status
