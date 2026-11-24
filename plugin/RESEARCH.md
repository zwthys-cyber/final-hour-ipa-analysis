# Native implementation notes

Exact main image UUID: `C180D5C9-19A5-3A9D-9F63-543607FDF175`.
Main image preferred base: `0x100000000`.

`TickAimAssist` (`0x107822e7c`) reads enable at `0x10eb22430`, ADS gate at `0x10eb22440`, search range at `0x10eb22458`, slowdown at `0x10eb22438`, and capture padding at `0x10eb2243c`.

`ApplyAimAssistFollow` (`0x107823b90`) checks enable, follow-on at `0x10eb22448` and positive follow weight at `0x10eb22444`. It clamps angular deltas to ±3 degrees before multiplying by that weight and adding to controller input. It also checks game state, target and view/input/movement conditions. Those checks remain in place.

| Unslid address | Observed value | Used as |
|---|---:|---|
| 0x10eb22430 | int 1 | enable |
| 0x10eb22438 | float 0.4 | slowdown |
| 0x10eb2243c | float 40 | capture padding (cm) |
| 0x10eb22440 | int 1 | ADS only |
| 0x10eb22444 | float 0.5 | follow multiplier |
| 0x10eb22448 | int 1 | follow on |
| 0x10eb22458 | float 5000 | search range (cm) |

The scalar interpretation comes from instruction usage and defaults; console variable spellings provide additional context. We do not claim that console variable registration was fully reconstructed. Unrelated words in this contiguous region are never written.

The plugin uses writable data only, with no function hooks, executable-page changes, private kernel interfaces, Unreal C++ ABI calls or third-party hooking dependency. It verifies UUID, two 16-byte code prefixes, accessible memory protections and plausible parameter values before enabling. The image-header address handles ASLR. The build-specific data offsets are intentionally rejected for any other UUID.

The timer touches seven naturally aligned 32-bit slots while active. Individual accesses are atomic; they are not a transactional update of the entire setting group. Disabling conditionally restores the saved values, avoiding overwriting later changes detected in those slots. No object pointer is stored between frames.

Device-level loadability and runtime gameplay behavior have not been tested. Ad hoc signing and a successful cross-compile do not establish that a particular injector/device will load the dylib.
