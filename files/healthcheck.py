#!/usr/bin/env python3

"""Healthcheck

A simple healthcheck to see if the ESMC service (port 2222)
and API (port 2223) are reachable.
"""

import socket
import sys


def main():

    """Check if ports 2222 and 2223 are reachable"""
    ports = [
        2222,
        2223
    ]

    for port in ports:

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.connect(('127.0.0.1', port))
            except ConnectionRefusedError:
                sys.exit(1)


if __name__ == "__main__":
    pass
