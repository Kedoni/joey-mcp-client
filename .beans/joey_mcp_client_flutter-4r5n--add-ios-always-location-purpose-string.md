---
# joey_mcp_client_flutter-4r5n
title: Add iOS always location purpose string
status: completed
type: bug
priority: normal
created_at: 2026-06-29T05:57:27Z
updated_at: 2026-06-29T05:59:25Z
---

Apple reported ITMS-90683 for missing NSLocationAlwaysAndWhenInUseUsageDescription in Info.plist. Add a clear purpose string for the location APIs referenced by dependencies and validate iOS build.