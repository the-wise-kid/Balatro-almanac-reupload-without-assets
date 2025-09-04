# Talisman
A mod for Balatro that increases the score cap from ~10^308 to ~10{1000}10, allowing for endless runs to go past "naneinf" and Ante 39, and removes the long animations that come with these scores.

The "BigNum" representation used by Talisman is a modified version of [this](https://github.com/veprogames/lua-big-number) library by veprogames.
The "OmegaNum" representation used by Talisman is a port of [OmegaNum.js](https://github.com/Naruyoko/OmegaNum.js/blob/master/OmegaNum.js) by [Mathguy23](https://github.com/Mathguy23)

## Installation
Talisman requires [Lovely](https://github.com/ethangreen-dev/lovely-injector) to be installed in order to be loaded by Balatro. The code for Talisman must be installed in `%AppData%/Balatro/Mods/Talisman`.

## Limitations
- High scores will not be saved to your profile (this is to prevent your profile save from being incompatible with an unmodified instance of Balatro)
- Savefiles created/opened with Talisman aren't backwards-compatible with unmodified versions of Balatro.
- Depending on the amount of retriggers, there may be lag when computing a score with Talisman.
- The largest ante before score requirements reach the new limit is approximately 2e153.
- When using Talisman with other mods, comparison operations with numbers used by scoring will not work by default (these must be handled by the mod developer).
