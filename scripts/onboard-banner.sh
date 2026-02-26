#!/usr/bin/env bash

# Show this only for interactive shells.
case "$-" in
  *i*) ;;
  *) return ;;
esac

echo
echo "Tip: run 'onboard' to install optional developer tools and nvm (Node 22 default)."
echo
