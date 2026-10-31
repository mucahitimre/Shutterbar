# Security Policy

## Supported versions

Only the latest release on the `main` branch receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private vulnerability reporting instead: **Security → Report a vulnerability** on this repository.

Include what you found, how to reproduce it and the macOS version. You should get a first reply within 7 days.

Areas of particular interest: anything that lets captured screen content leave the user's control (files written outside the chosen folder, clipboard or notification leaks), sandbox escapes, and permission handling.
