#!/usr/bin/env python3
"""Select an available exact model on the pinned OS by UUID (tvOS A0 pattern)."""
import json
import sys

def select(devices, name):
    for device in devices.get('com.apple.CoreSimulator.SimRuntime.iOS-27-2', []):
        if device.get('isAvailable') and device.get('name') == name:
            return device['udid']
    raise ValueError(f'Install an available {name} simulator on iOS 27.2 in the default device set.')

if __name__ == '__main__':
    try:
        print(select(json.load(sys.stdin)['devices'], sys.argv[1]))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
