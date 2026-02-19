## Build Requirements

**This project runs in an ARM Linux container with NO Android SDK or JDK installed.**

For any Android-related builds (NDK compilation, APK packaging, Gradle tasks), you MUST use `orbital`:

```bash
# Android builds via orbital (replaces ./gradlew or direct ndk-build)
orbital build . assembleDebug
orbital build . <gradle-tasks...>

# Pass properties
orbital build . assembleDebug -- -Pproperty=value
```

**NEVER run `./gradlew`, `gradle`, `ndk-build`, or `java` directly — they will fail.**
Always use `orbital build` for anything that requires the Android SDK or JDK.

For non-Android builds (CMake/desktop targets), use standard CMake commands locally.

## Escalation Path

When you're blocked on something you can't resolve alone, escalate to the Mayor:

```bash
gt mail send mayor/ -s "Need help: <brief>" -m "<details>"
gt nudge mayor "Check mail — I'm blocked on <topic>"
```

**When to escalate:**
- Cross-rig issues (need changes in another repo)
- Need human decision (design direction, access, approval)
- Blocked on external dependency or infrastructure
- Stuck for >15 min with no progress

**What happens:** Mayor coordinates across rigs and relays to the host-liaison
(an AI agent on the host machine), who coordinates with Misha (the human overseer).

**Nudges from `[host-liaison]`** (arriving as `[from unknown]`) come from the host-side
AI liaison — not the human directly. Acknowledge and act on them.
