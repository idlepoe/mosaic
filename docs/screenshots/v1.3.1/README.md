# Compact button validation (1.3.1)

Captured through scrcpy on the SM-S931N physical phone (Android 16) on November 6,
2026, using the separate `.dev` test application. The legacy app is preserved.

[01-compact-buttons.jpg](01-compact-buttons.jpg) shows the gallery action and
bottom generation action after removal of duplicate label padding. Both are now
compact while preserving a 44 logical pixel minimum height; supporting and choice
buttons have a 40 logical pixel minimum. Wrapped or enlarged text can increase
the height rather than being clipped.

Flutter analysis and all 33 existing tests passed, including 160% text in both
themes. Debug and release ARM64 builds succeeded. Android release version is
1.3.1 / version code 2008, signed with the existing release certificate.
